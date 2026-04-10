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

    // Interests
    @Published var followedLeagueIds: Set<Int> = []
    @Published var followedTeamNames: Set<String> = []
    @Published var showInterestsPicker = false

    // Match data
    @Published var allMatches: [Match] = []

    private let supabaseManager = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()

    // Computed: upcoming + live matches filtered by user's interests
    var suggestedMatches: [Match] {
        guard !followedLeagueIds.isEmpty || !followedTeamNames.isEmpty else {
            return []
        }

        return allMatches.filter { match in
            let leagueMatch = followedLeagueIds.contains(match.leagueId)
            let teamMatch   = followedTeamNames.contains(match.home)
                           || followedTeamNames.contains(match.away)
            return leagueMatch || teamMatch
        }
        .sorted { m1, m2 in
            if m1.isLive != m2.isLive { return m1.isLive }
            return m1.rawDate < m2.rawDate
        }
    }

    // Computed: only live matches for the Live tab
    var liveMatches: [Match] {
        allMatches.filter { $0.isLive }
    }

    init() {
        supabaseManager.$user
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                if user != nil {
                    Task { await self?.load() }
                }
            }
            .store(in: &cancellables)
    }

    func load() async {
        guard supabaseManager.user != nil else { return }

        isLoading = true
        errorMessage = nil

        do {
            async let feedTask    = supabaseManager.fetchFeed()
            async let myPicksTask = supabaseManager.fetchMyPicks()
            async let profileTask = supabaseManager.fetchUserProfile()
            async let matchesTask = APIManager.fetchAllMatches()

            let (feed, picks, profile, matches) = try await (feedTask, myPicksTask, profileTask, matchesTask)

            self.feedPicks   = feed
            self.myPicks     = picks
            self.userProfile = profile
            self.allMatches  = matches

            // Load saved interests from profile
            loadInterestsFromProfile(profile)

            print("✅ Feed loaded: \(feed.count) picks, \(matches.count) matches")
        } catch {
            print("❌ Feed error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }

    // MARK: - Interests Persistence

    private func loadInterestsFromProfile(_ profile: UserProfile?) {
        // Leagues stored as comma-separated IDs e.g. "39,140,2"
        if let leagueStr = profile?.favourite_league, !leagueStr.isEmpty {
            let ids = leagueStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            followedLeagueIds = Set(ids)
        }

        // Teams stored as comma-separated names e.g. "Arsenal,Liverpool"
        if let teamStr = profile?.favourite_team, !teamStr.isEmpty {
            let names = teamStr.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            followedTeamNames = Set(names)
        }
    }

    func saveInterests() async {
        guard let userId = supabaseManager.user?.id else { return }

        let leagueStr = followedLeagueIds.map(String.init).joined(separator: ",")
        let teamStr   = followedTeamNames.joined(separator: ",")

        do {
            try await supabaseManager.client
                .from("profiles")
                .update([
                    "favourite_league": leagueStr,
                    "favourite_team":   teamStr
                ])
                .eq("id", value: userId.uuidString.lowercased())
                .execute()

            print("✅ Interests saved: leagues=\(leagueStr) teams=\(teamStr)")
        } catch {
            print("❌ Failed to save interests: \(error.localizedDescription)")
        }
    }

    // MARK: - Auth

    func logout() async {
        do {
            try await supabaseManager.logout()
            feedPicks    = []
            myPicks      = []
            userProfile  = nil
            allMatches   = []
            followedLeagueIds = []
            followedTeamNames = []
        } catch {
            print("Logout error: \(error)")
        }
    }
}
