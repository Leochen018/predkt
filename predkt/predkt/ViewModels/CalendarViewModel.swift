import Foundation
import Combine
import Supabase  // ✅needed for client methods
import Auth      //  needed for user.id

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var allPicks: [Pick] = []       // all user picks (for calendar dots)
    @Published var todayPicks: [Pick] = []     // today's picks (for preview)
    @Published var selectedDayPicks: [Pick] = [] // picks for tapped day

    @Published var currentWinStreak: Int = 0
    @Published var dailyStreak: Int = 0
    @Published var totalXP: Int = 0
    @Published var isLoading = false

    private let supabaseManager = SupabaseManager.shared

    // MARK: - Load all picks (for calendar dot rendering)

    func loadAllPicks() async {
        guard let userId = supabaseManager.user?.id else { return }
        do {
            let response = try await supabaseManager.client
                .from("picks")
                .select("*")
                .eq("user_id", value: userId.uuidString.lowercased())
                .order("created_at", ascending: false)
                .execute()
            allPicks = try JSONDecoder().decode([Pick].self, from: response.data)
            todayPicks = picks(for: Date())
        } catch {
            print("❌ Calendar load error: \(error)")
        }

        // Load streak + XP from profile
        if let profile = try? await supabaseManager.fetchUserProfile() {
            currentWinStreak = profile.current_streak ?? 0
            dailyStreak      = profile.daily_streak ?? 0
            totalXP          = profile.total_points ?? 0
        }
    }

    // MARK: - Load picks for a specific date

    func loadPicks(for date: Date) async {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]

        guard let userId = supabaseManager.user?.id else { return }
        isLoading = true
        do {
            let response = try await supabaseManager.client
                .from("picks")
                .select("*")
                .eq("user_id", value: userId.uuidString.lowercased())
                .gte("created_at", value: f.string(from: start))
                .lt("created_at", value: f.string(from: end))
                .order("created_at", ascending: false)
                .execute()
            selectedDayPicks = try JSONDecoder().decode([Pick].self, from: response.data)
        } catch {
            print("❌ Day picks error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Get picks for a calendar date (from cached allPicks)

    func picks(for date: Date) -> [Pick] {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]

        return allPicks.filter { pick in
            guard let d = f1.date(from: pick.created_at) ?? f2.date(from: pick.created_at) else { return false }
            return d >= start && d < end
        }
    }

    // MARK: - Streak multiplier text (for display)

    var streakMultiplierText: String {
        let multiplier = min(2.0, 1.0 + Double(currentWinStreak) * 0.1)
        return String(format: "×%.1f", multiplier)
    }

    var dailyBonusText: String {
        dailyStreak >= 2 ? "×1.2 daily bonus active" : "Play tomorrow to activate daily bonus"
    }
}
