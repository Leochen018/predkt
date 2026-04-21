import SwiftUI

@main
struct predktApp: App {
    // This creates the single source of truth for the whole app
    @StateObject private var supabaseManager = SupabaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabaseManager)
        }
    }
}
