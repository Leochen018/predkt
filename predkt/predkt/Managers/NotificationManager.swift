import Foundation
import UserNotifications
import UIKit
import Combine 

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var isAuthorized = false

    private init() {
        Task { await checkStatus() }
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted { print("✅ Notifications authorised") }
        } catch {
            print("❌ Notification permission error: \(error)")
        }
    }

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule Match Kickoff Reminder
    // Called when user locks in a prediction for a match

    func scheduleKickoffReminder(for match: Match) {
        guard isAuthorized else { return }

        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        guard let kickoff = f1.date(from: match.rawDate) ?? f2.date(from: match.rawDate) else { return }

        // Notify 15 minutes before kickoff
        let fireDate = kickoff.addingTimeInterval(-15 * 60)
        guard fireDate > Date() else { return } // skip if already past

        let content        = UNMutableNotificationContent()
        content.title      = "⚽ Kick off in 15 mins!"
        content.body       = "\(match.home) vs \(match.away) — \(match.competition)"
        content.sound      = .default
        content.userInfo   = ["matchId": match.id, "type": "kickoff"]

        let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
        let trigger    = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request    = UNNotificationRequest(identifier: "kickoff_\(match.id)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("❌ Kickoff notification error: \(err)") }
            else { print("🔔 Kickoff reminder set for \(match.home) vs \(match.away)") }
        }
    }

    // MARK: - Prediction Confirmed Notification (immediate)

    func notifyPickConfirmed(match: String, market: String, xp: Int) {
        guard isAuthorized else { return }

        let content   = UNMutableNotificationContent()
        content.title = "✅ Play locked in!"
        content.body  = "\(market) — \(match) · +\(xp) XP at stake"
        content.sound = .default
        content.userInfo = ["type": "pick_confirmed"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "pick_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Prediction Result Notification

    func notifyPickResult(match: String, market: String, result: String, xpEarned: Int) {
        guard isAuthorized else { return }

        let won     = result == "correct"
        let content = UNMutableNotificationContent()
        content.title = won ? "🎉 Correct! XP earned!" : "❌ Unlucky this time"
        content.body  = won
            ? "\(market) came in — +\(xpEarned) XP added to your total!"
            : "\(market) didn't land for \(match)"
        content.sound = won ? .defaultRingtone : .default
        content.badge = 1
        content.userInfo = ["type": "pick_result", "result": result]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "result_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Streak Milestone Notification

    func notifyStreakMilestone(streak: Int) {
        guard isAuthorized, streak > 0, streak % 3 == 0 else { return }

        let content   = UNMutableNotificationContent()
        content.title = "🔥 \(streak) win streak!"
        content.body  = "You're on fire — keep going for bigger XP multipliers!"
        content.sound = .default
        content.userInfo = ["type": "streak"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "streak_\(streak)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Daily Reminder (if no pick today)

    func scheduleDailyReminder() {
        guard isAuthorized else { return }
        // Cancel any existing daily reminder first
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])

        let content   = UNMutableNotificationContent()
        content.title = "⚽ Don't break your streak!"
        content.body  = "Today's matches are live — make your plays to keep your daily streak going."
        content.sound = .default
        content.userInfo = ["type": "daily"]

        // Fire at 18:00 every day
        var components    = DateComponents()
        components.hour   = 18
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Cancel notifications for a match (e.g. if match cancelled)

    func cancelKickoffReminder(for matchId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["kickoff_\(matchId)"])
    }

    // MARK: - Clear badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
    }
}
