import Foundation
import Combine
import Supabase  // needed for client methods
import Auth      // needed for user.id

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var allPicks: [Pick] = []          // all user picks (for calendar dots)
    @Published var todayPicks: [Pick] = []        // today's picks (for preview)
    @Published var selectedDayPicks: [Pick] = []  // picks for tapped day

    @Published var currentWinStreak: Int = 0
    @Published var dailyStreak: Int = 0
    @Published var totalXP: Int = 0
    @Published var isLoading = false

    // Step 2 — offline banner state
    @Published var isOffline = false

    private let supabaseManager = SupabaseManager.shared
    private let network = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Step 2 — watch network, auto-retry loadAllPicks when connection comes back
        network.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isOffline = !connected
                // Step 5 — if we just came back online and have no picks, reload
                if connected && (self?.allPicks.isEmpty ?? true) {
                    Task { await self?.loadAllPicks() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load all picks (for calendar dot rendering)

    func loadAllPicks() async {
        guard let userId = supabaseManager.user?.id else { return }

        // Step 3 — don't attempt the fetch if we're offline; keep whatever data we have
        guard network.isConnected else {
            if allPicks.isEmpty {
                // Only show a message if there's nothing cached to show
                print("📵 Calendar offline — no cached picks")
            }
            return
        }

        // Step 5 — retry with exponential backoff (up to 3 attempts)
        for attempt in 1...3 {
            do {
                let response = try await supabaseManager.client
                    .from("picks")
                    .select("*")
                    .eq("user_id", value: userId.uuidString.lowercased())
                    .order("created_at", ascending: false)
                    .execute()

                // Step 1 — only update data on success, never clear on failure
                allPicks   = try JSONDecoder().decode([Pick].self, from: response.data)
                todayPicks = picks(for: Date())

                // Load streak + XP from profile (best-effort, not retried)
                if let profile = try? await supabaseManager.fetchUserProfile() {
                    currentWinStreak = profile.current_streak ?? 0
                    dailyStreak      = profile.daily_streak ?? 0
                    totalXP          = profile.total_points ?? 0
                }

                break  // success — stop retrying

            } catch {
                print("❌ Calendar load attempt \(attempt)/3: \(error.localizedDescription)")
                if attempt < 3 {
                    // Step 5 — exponential backoff: 1s then 2s
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
                // Step 1 — on final failure, allPicks is untouched — old data stays visible
            }
        }
    }

    // MARK: - Load picks for a specific date

    func loadPicks(for date: Date) async {
        guard let userId = supabaseManager.user?.id else { return }

        // Step 3 — offline guard for per-day fetch (fall back to cached allPicks)
        guard network.isConnected else {
            // Serve from the already-cached allPicks so the day view still works offline
            selectedDayPicks = picks(for: date)
            return
        }

        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]

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

            // Step 1 — only assign on success; selectedDayPicks keeps its old value on failure
            selectedDayPicks = try JSONDecoder().decode([Pick].self, from: response.data)
        } catch {
            // Step 1 — fetch failed: fall back to cached allPicks so something shows
            selectedDayPicks = picks(for: date)
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

    var picksByDate: [(date: Date, picks: [Pick])] {
        let cal = Calendar.current
        let f1  = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2  = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]

        var grouped: [Date: [Pick]] = [:]
        for pick in allPicks {
            guard let d = f1.date(from: pick.created_at) ?? f2.date(from: pick.created_at) else { continue }
            let day = cal.startOfDay(for: d)
            grouped[day, default: []].append(pick)
        }

        return grouped
            .map { (date: $0.key, picks: $0.value) }
            .sorted { $0.date > $1.date }
    }
}
