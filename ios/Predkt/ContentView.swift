import SwiftUI

struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager

    var body: some View {
        if supabaseManager.user != nil {
            MainTabView()
        } else {
            AuthView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SupabaseManager.shared)
}
