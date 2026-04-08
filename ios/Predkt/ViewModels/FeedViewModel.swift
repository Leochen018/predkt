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

    func load() async {
        isLoading = true
        errorMessage = nil

        async let feedTask = supabaseManager.fetchFeed()
        async let myPicksTask = supabaseManager.fetchMyPicks()
        async let profileTask = supabaseManager.fetchUserProfile()

        do {
            let (feed, myPicks, profile) = try await (feedTask, myPicksTask, profileTask)
            self.feedPicks = feed
            self.myPicks = myPicks
            self.userProfile = profile
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }
}
