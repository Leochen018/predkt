import Foundation
import Supabase
import Combine

struct LeaderboardEntry: Identifiable, Decodable {
    let id: String
    let username: String
    let total_points: Int?
    let weekly_points: Int?
    let best_streak: Int?
    let current_streak: Int?

    var displayXP: Int { total_points ?? 0 }
    var weeklyXP: Int  { weekly_points ?? 0 }
    var streak: Int    { current_streak ?? 0 }
}

struct League: Identifiable, Decodable {
    let id: String
    let name: String
    let invite_code: String
    let created_by: String?
    let is_public: Bool?
}

struct LeagueMember: Decodable {
    let user_id: String
    let profiles: LeaderboardEntry?
}

@MainActor
final class LeagueViewModel: ObservableObject {
    @Published var globalLeaderboard: [LeaderboardEntry] = []
    @Published var weeklyLeaderboard: [LeaderboardEntry] = []
    @Published var myLeagues: [League] = []
    @Published var selectedLeague: League?
    @Published var leagueLeaderboard: [LeaderboardEntry] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var showCreateLeague = false
    @Published var showJoinLeague   = false
    @Published var newLeagueName    = ""
    @Published var joinCode         = ""
    @Published var actionMessage: String?

    // Merged local + remote banned words — used by CreateLeagueSheet
    @Published var bannedWords: Set<String> = []

    private let supabaseManager = SupabaseManager.shared

    // Replace with your Railway base URL
    private let backendURL = "https://your-railway-app.up.railway.app"

    // Local list — instant, no network needed
    private let localBannedWords: Set<String> = [
        "fuck", "shit", "bitch", "asshole", "cunt", "dick", "pussy",
        "nigger", "nigga", "faggot", "retard", "whore", "slut",
        "bastard", "cock", "twat", "wanker",
        "nazi", "hitler", "kkk", "isis", "isil", "jihad", "hamas",
        "nonce", "pedo", "paedo", "paedophile", "pedophile",
        "n1gger", "f4ggot", "p3do", "naz1"
    ]

    // MARK: - Load All

    func load() async {
        isLoading = true; errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchGlobalLeaderboard() }
            group.addTask { await self.fetchWeeklyLeaderboard() }
            group.addTask { await self.fetchMyLeagues() }
            group.addTask { await self.syncBannedWords() }
        }
        isLoading = false
    }

    // MARK: - Banned Words Sync

    func syncBannedWords() async {
        // Always start with the local list so validation works instantly
        bannedWords = localBannedWords

        do {
            let response = try await supabaseManager.client
                .from("banned_words")
                .select("word")
                .execute()
            struct BannedWord: Decodable { let word: String }
            let remote = try JSONDecoder().decode([BannedWord].self, from: response.data)
            // Merge remote words into the set
            bannedWords = bannedWords.union(remote.map { $0.word.lowercased() })
            print("✅ Banned words synced — \(bannedWords.count) total")
        } catch {
            // Local list is already set — fail silently
            print("⚠️ Could not sync remote banned words, using local list")
        }
    }

    // MARK: - Leaderboards

    func fetchGlobalLeaderboard() async {
        do {
            let response = try await supabaseManager.client
                .from("profiles")
                .select("id, username, total_points, weekly_points, best_streak, current_streak")
                .order("total_points", ascending: false)
                .limit(50)
                .execute()
            globalLeaderboard = try JSONDecoder().decode([LeaderboardEntry].self, from: response.data)
        } catch {
            print("❌ Global LB error: \(error)")
        }
    }

    func fetchWeeklyLeaderboard() async {
        do {
            let response = try await supabaseManager.client
                .from("profiles")
                .select("id, username, total_points, weekly_points, best_streak, current_streak")
                .order("weekly_points", ascending: false)
                .limit(50)
                .execute()
            weeklyLeaderboard = try JSONDecoder().decode([LeaderboardEntry].self, from: response.data)
        } catch {
            print("❌ Weekly LB error: \(error)")
        }
    }

    // MARK: - My Leagues

    func fetchMyLeagues() async {
        guard let userId = supabaseManager.user?.id else { return }
        do {
            let memberResponse = try await supabaseManager.client
                .from("league_members")
                .select("league_id")
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()

            struct MemberRow: Decodable { let league_id: String }
            let memberRows = try JSONDecoder().decode([MemberRow].self, from: memberResponse.data)
            let leagueIds  = memberRows.map { $0.league_id }

            guard !leagueIds.isEmpty else { myLeagues = []; return }

            let leagueResponse = try await supabaseManager.client
                .from("leagues")
                .select("*")
                .in("id", values: leagueIds)
                .execute()
            myLeagues = try JSONDecoder().decode([League].self, from: leagueResponse.data)
        } catch {
            print("❌ My leagues error: \(error)")
        }
    }

    func fetchLeagueLeaderboard(for league: League) async {
        selectedLeague = league
        isLoading = true
        do {
            let response = try await supabaseManager.client
                .from("league_members")
                .select("user_id, profiles(id, username, total_points, weekly_points, best_streak, current_streak)")
                .eq("league_id", value: league.id)
                .execute()

            struct MemberWithProfile: Decodable {
                let user_id: String
                let profiles: LeaderboardEntry?
            }
            let members = try JSONDecoder().decode([MemberWithProfile].self, from: response.data)
            leagueLeaderboard = members
                .compactMap { $0.profiles }
                .sorted { ($0.total_points ?? 0) > ($1.total_points ?? 0) }
        } catch {
            print("❌ League LB error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Create League

    func createLeague() async {
        let name = newLeagueName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { actionMessage = "Enter a league name"; return }
        guard let userId = supabaseManager.user?.id else { return }

        // API moderation check
        let isSafe = await checkNameWithAPI(name)
        guard isSafe else {
            actionMessage = "That name was flagged — please choose another"
            return
        }

        let code = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })

        do {
            let response = try await supabaseManager.client
                .from("leagues")
                .insert([
                    "name":        name,
                    "invite_code": code,
                ])
                .select()
                .single()
                .execute()

            struct CreatedLeague: Decodable { let id: String }
            let created = try JSONDecoder().decode(CreatedLeague.self, from: response.data)

            // Auto-join the creator
            try await supabaseManager.client
                .from("league_members")
                .insert([
                    "league_id": created.id,
                    "user_id":   userId.uuidString.lowercased(),
                ])
                .execute()

            newLeagueName = ""
            showCreateLeague = false
            actionMessage = "Squad created! Code: \(code)"
            await fetchMyLeagues()
        } catch {
            actionMessage = "Failed to create: \(error.localizedDescription)"
        }
    }

    // MARK: - Join League

    func joinLeague() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { actionMessage = "Enter an invite code"; return }
        guard let userId = supabaseManager.user?.id else { return }

        do {
            let leagueResponse = try await supabaseManager.client
                .from("leagues")
                .select("id, name")
                .eq("invite_code", value: code)
                .single()
                .execute()

            struct FoundLeague: Decodable { let id: String; let name: String }
            let league = try JSONDecoder().decode(FoundLeague.self, from: leagueResponse.data)

            try await supabaseManager.client
                .from("league_members")
                .insert([
                    "league_id": league.id,
                    "user_id":   userId.uuidString.lowercased(),
                ])
                .execute()

            joinCode = ""
            showJoinLeague = false
            actionMessage = "Joined \(league.name)!"
            await fetchMyLeagues()
        } catch {
            actionMessage = "Invalid code or already a member"
        }
    }

    // MARK: - Name Moderation

    private func checkNameWithAPI(_ name: String) async -> Bool {
        guard let url = URL(string: "\(backendURL)/api/check-name") else { return true }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode([String: Bool].self, from: data)
            return result["safe"] ?? true
        } catch {
            // Fail open — don't block users if the API is unreachable
            print("⚠️ Name check unavailable: \(error.localizedDescription)")
            return true
        }
    }
}
