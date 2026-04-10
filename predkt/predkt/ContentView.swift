import SwiftUI
import Combine
struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager

    var body: some View {
        Group {
            // This is the critical check
            if supabaseManager.session != nil {
                MainTabView()
            } else {
                AuthView() // This should show if session is missing
            }
        }
        // This ensures the screen swaps immediately when logout is pressed
        .animation(.default, value: supabaseManager.session == nil)
    }
}
