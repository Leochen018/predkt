import SwiftUI
import Supabase

@main
struct predktApp: App {
    // 1. Initialize the SupabaseManager as a StateObject
    // This keeps the database connection alive as long as the app is open.
    @StateObject private var supabaseManager = SupabaseManager.shared

    var body: some Scene {
        WindowGroup {
            // 2. We use a Group to check if the user is logged in
            Group {
                if supabaseManager.session != nil {
                    // User is logged in, show the main app
                    MainTabView()
                } else {
                    // No session found. For now, we'll show the MainTabView
                    // so you can see your UI work, but later you can
                    // swap this with a LoginView()
                    MainTabView()
                }
            }
            // 3. This is CRITICAL: it passes the database manager to every
            // other view in your app so things like 'Profile' and 'Picks' work.
            .environmentObject(supabaseManager)
            
            // 4. Force the app into Dark Mode to match your design
            .preferredColorScheme(.dark)
        }
    }
}
