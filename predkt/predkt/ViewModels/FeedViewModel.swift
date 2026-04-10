import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var feedPicks: [Pick] = []
    @Published var myPicks: [Pick] = []
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseManager = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Automatically reload whenever the user session changes
        // This fixes the "Blank Feed on launch" issue
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
        guard supabaseManager.user != nil else {
            // Silently return if no user; ContentView handles the Auth redirect
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Parallel fetching (The "Kitchen" is now preparing all three plates at once)
            async let feedTask = supabaseManager.fetchFeed()
            async let myPicksTask = supabaseManager.fetchMyPicks()
            async let profileTask = supabaseManager.fetchUserProfile()

            let (feed, myPicks, profile) = try await (feedTask, myPicksTask, profileTask)
            
            self.feedPicks = feed
            self.myPicks = myPicks
            self.userProfile = profile
            
            print("✅ Data Sync Complete: \(feed.count) public, \(myPicks.count) private")
        } catch {
            print("❌ Sync Error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }
    
    func logout() async {
        do {
            try await supabaseManager.logout()
            // Clear everything so the next user doesn't see old data
            self.feedPicks = []
            self.myPicks = []
            self.userProfile = nil
        } catch {
            print("Logout error: \(error)")
        }
    }
}
