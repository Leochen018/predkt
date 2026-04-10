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

    private let supabaseManager = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()

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
    }

    func load() async {
        guard supabaseManager.user != nil else { return }
        isLoading = true; errorMessage = nil
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
            loadInterestsFromProfile(profile)
            print("✅ Feed loaded: \(feed.count) picks, \(matches.count) matches")
        } catch {
            print("❌ Feed error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async { await load() }

    // MARK: - Delete Pick

    func deletePick(_ pick: Pick) async {
        guard pick.result == "pending" else { return }
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
            feedPicks = []; myPicks = []; userProfile = nil; allMatches = []
            followedLeagueIds = []; followedTeamNames = []
        } catch { print("Logout error: \(error)") }
    }
}
