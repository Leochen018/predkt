import Foundation
import UserNotifications
import UIKit
import Combine

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var isAuthorized = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        Task { await checkStatus() }

        // ✅ Re-check status every time app comes to foreground
        // This catches when user enables/disables in iOS Settings
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.checkStatus() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Check

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
        // Only update if changed — avoids unnecessary re-renders
        if isAuthorized != authorized { isAuthorized = authorized }
    }

    // MARK: - Request Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                scheduleDailyReminder()
                print("✅ Notifications authorised")
            }
        } catch {
            print("❌ Notification permission error: \(error)")
        }
    }

    // MARK: - Open iOS Settings (for disabling)
    // iOS doesn't allow apps to revoke permission — must go to Settings

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Kickoff Reminder

    func scheduleKickoffReminder(for match: Match) {
        guard isAuthorized else { return }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        guard let kickoff = f1.date(from: match.rawDate) ?? f2.date(from: match.rawDate) else { return }
        let fireDate = kickoff.addingTimeInterval(-15 * 60)
        guard fireDate > Date() else { return }

        let content      = UNMutableNotificationContent()
        content.title    = "⚽ Kick off in 15 mins!"
        content.body     = "\(match.home) vs \(match.away) — \(match.competition)"
        content.sound    = .default
        content.userInfo = ["matchId": match.id, "type": "kickoff"]

        let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
        let trigger    = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request    = UNNotificationRequest(identifier: "kickoff_\(match.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("❌ Kickoff notif: \(err)") }
        }
    }

    // MARK: - Pick Confirmed

    func notifyPickConfirmed(match: String, market: String, xp: Int) {
        guard isAuthorized else { return }
        let content   = UNMutableNotificationContent()
        content.title = "✅ Play locked in!"
        content.body  = "\(market) — \(match) · +\(xp) XP at stake"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "pick_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Result Notification

    func notifyPickResult(match: String, market: String, result: String, xpEarned: Int) {
        guard isAuthorized else { return }
        let won     = result == "correct"
        let content = UNMutableNotificationContent()
        content.title = won ? "🎉 Correct! XP earned!" : "❌ Unlucky this time"
        content.body  = won ? "\(market) came in — +\(xpEarned) XP!" : "\(market) didn't land for \(match)"
        content.sound = .default
        content.badge = 1
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "result_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Streak Milestone

    func notifyStreakMilestone(streak: Int) {
        guard isAuthorized, streak > 0, streak % 3 == 0 else { return }
        let content   = UNMutableNotificationContent()
        content.title = "🔥 \(streak) win streak!"
        content.body  = "You're on fire — keep going for bigger XP multipliers!"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "streak_\(streak)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Daily Reminder

    func scheduleDailyReminder() {
        guard isAuthorized else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        let content   = UNMutableNotificationContent()
        content.title = "⚽ Don't break your streak!"
        content.body  = "Today's matches are live — make your plays to keep your daily streak going."
        content.sound = .default
        var components  = DateComponents()
        components.hour = 18; components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Cancel / Clear

    func cancelKickoffReminder(for matchId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["kickoff_\(matchId)"])
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
    }
}
