import UIKit
import UserNotifications
import Auth
import PostgREST
import Supabase

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    // Called when iOS gives you a device token
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await savePushToken(token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error)")
    }

    private func savePushToken(_ token: String) async {
        guard let userId = SupabaseManager.shared.user?.id else { return }
        do {
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(["push_token": token])
                .eq("id", value: userId.uuidString.lowercased())
                .execute()
            print("Push token saved")
        } catch {
            print("Failed to save push token: \(error)")
        }
    }
}
