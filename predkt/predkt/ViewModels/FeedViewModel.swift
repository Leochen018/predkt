import Foundation
import Combine
import Supabase

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var feedPicks: [Pick] = []
    @Published var myPicks: [Pick] = []
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var followedLeagueIds: Set<Int> = []
    @Published var followedTeamNames: Set<String> = []
    @Published var showInterestsPicker = false

    @Published var allMatches: [Match] = []

    // Step 2 — offline banner state
    @Published var isOffline = false

    private let supabaseManager = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let network = NetworkMonitor.shared

    var suggestedMatches: [Match] {
        guard !followedLeagueIds.isEmpty || !followedTeamNames.isEmpty else { return [] }
        return allMatches.filter { match in
            followedLeagueIds.contains(match.leagueId) ||
            followedTeamNames.contains(match.home) ||
            followedTeamNames.contains(match.away)
        }
        .sorted { m1, m2 in m1.isLive != m2.isLive ? m1.isLive : m1.rawDate < m2.rawDate }
    }

    var liveMatches: [Match] { allMatches.filter { $0.isLive } }

    init() {
        supabaseManager.$user
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                if user != nil { Task { await self?.load() } }
            }
            .store(in: &cancellables)

        // Step 2 — mirror network state into published var for views
        network.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isOffline = !connected
                // Step 5 — auto-retry when connection comes back
                if connected { Task { await self?.load() } }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load (Step 1 + Step 5: retry with backoff)

    func load(retryCount: Int = 3) async {
        guard supabaseManager.user != nil else { return }

        // Step 3 — don't even try if we know we're offline
        guard network.isConnected else {
            errorMessage = "No connection — showing cached data"
            return
        }

        isLoading = true; errorMessage = nil

        for attempt in 1...retryCount {
            do {
                async let feedTask    = supabaseManager.fetchFeed()
                async let myPicksTask = supabaseManager.fetchMyPicks()
                async let profileTask = supabaseManager.fetchUserProfile()
                async let matchesTask = APIManager.fetchAllMatches()
                let (feed, picks, profile, matches) = try await (feedTask, myPicksTask, profileTask, matchesTask)

                // Step 1 — only update data on success, never clear on failure
                self.feedPicks   = feed
                self.myPicks     = picks
                self.userProfile = profile
                self.allMatches  = matches
                loadInterestsFromProfile(profile)
                print("✅ Feed loaded: \(feed.count) picks, \(matches.count) matches")

                // Grade any pending picks for finished matches
                await gradeAndSyncPicks()
                break  // success — stop retrying

            } catch {
                print("❌ Feed attempt \(attempt)/\(retryCount): \(error.localizedDescription)")

                if attempt < retryCount {
                    // Step 5 — exponential backoff: 1s, 2s, 4s
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    // All retries failed — show error but keep old data visible
                    errorMessage = "Couldn't refresh — showing last known data"
                }
            }
        }

        isLoading = false
    }

    func refresh() async { await load() }

    // MARK: - Grade Picks

    
    private struct PickResultUpdate: Encodable {
        let result: String
        let points_earned: Int
    }
    private func gradeAndSyncPicks() async {
        let pending = myPicks.filter { $0.result == "pending" }
        guard !pending.isEmpty else { return }
        
        print("🔍 Pending picks: \(pending.count)")
         for pick in pending {
             let matchFound = allMatches.first(where: { $0.displayName == pick.match })
             let finishedMatch = allMatches.first(where: { $0.displayName == pick.match && $0.isFinished })
             print("  → \(pick.match) | \(pick.market)")
             print("    match in allMatches: \(matchFound != nil) | isFinished: \(finishedMatch != nil)")
         }
        
        var gradedAny = false

        for pick in pending {
            // Find the finished match for this pick
            guard let match = allMatches.first(where: {
                $0.displayName == pick.match && $0.isFinished
            }) else { continue }

            guard let result = PickGrader.grade(
                market: pick.market,
                home: match.home,
                away: match.away,
                homeGoals: match.homeGoals,
                awayGoals: match.awayGoals
            ) else { continue }  // market not resolvable from final score — leave pending

            let earned = result == "correct" ? pick.points_possible : 0

            do {
                try await supabaseManager.client
                    .from("picks")
                    .update(PickResultUpdate(result: result, points_earned: earned))
                    .eq("id", value: pick.id)
                    .execute()
                gradedAny = true
                print("✅ Graded \(pick.market) (\(pick.match)) → \(result)")
            } catch {
                print("❌ Failed to grade pick \(pick.id): \(error)")
            }
        }

        // Reload picks to reflect updated results in the UI
        if gradedAny {
            if let freshPicks = try? await supabaseManager.fetchMyPicks() {
                myPicks = freshPicks
            }
            if let freshFeed = try? await supabaseManager.fetchFeed() {
                feedPicks = freshFeed
            }
        }
    }

    // MARK: - Delete Pick

    func deletePick(_ pick: Pick) async {
        guard pick.result == "pending" else { return }
        // Step 3 — guard offline before destructive network action
        guard network.isConnected else {
            errorMessage = "No connection — can't delete right now"
            return
        }
        do {
            try await supabaseManager.client
                .from("picks")
                .delete()
                .eq("id", value: pick.id)
                .execute()
            myPicks.removeAll   { $0.id == pick.id }
            feedPicks.removeAll { $0.id == pick.id }
        } catch {
            print("❌ Delete pick error: \(error)")
        }
    }

    // MARK: - Interests

    private func loadInterestsFromProfile(_ profile: UserProfile?) {
        if let s = profile?.favourite_league, !s.isEmpty {
            followedLeagueIds = Set(s.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        if let s = profile?.favourite_team, !s.isEmpty {
            followedTeamNames = Set(s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
    }

    func saveInterests() async {
        guard let userId = supabaseManager.user?.id else { return }
        guard network.isConnected else { errorMessage = "No connection — interests not saved"; return }
        do {
            try await supabaseManager.client
                .from("profiles")
                .update([
                    "favourite_league": followedLeagueIds.map(String.init).joined(separator: ","),
                    "favourite_team":   followedTeamNames.joined(separator: ","),
                ])
                .eq("id", value: userId.uuidString.lowercased())
                .execute()
        } catch { print("❌ Save interests: \(error)") }
    }

    func logout() async {
        do {
            try await supabaseManager.logout()
            // Intentional clear on logout — this is correct behaviour
            feedPicks = []; myPicks = []; userProfile = nil; allMatches = []
            followedLeagueIds = []; followedTeamNames = []
        } catch { print("Logout error: \(error)") }
    }
}
