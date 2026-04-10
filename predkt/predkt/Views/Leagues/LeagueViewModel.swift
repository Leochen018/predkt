import Foundation
import Supabase

struct LeaderboardEntry: Identifiable, Decodable {
    let id: String
    let username: String
    let total_points: Int?
    let weekly_points: Int?
    let best_streak: Int?
    let current_streak: Int?

    var displayXP: Int     { total_points ?? 0 }
    var weeklyXP: Int      { weekly_points ?? 0 }
    var streak: Int        { current_streak ?? 0 }
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

    private let supabaseManager = SupabaseManager.shared

    // MARK: - Load All

    func load() async {
        isLoading = true; errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchGlobalLeaderboard() }
            group.addTask { await self.fetchWeeklyLeaderboard() }
            group.addTask { await self.fetchMyLeagues() }
        }
        isLoading = false
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
            // Get league IDs the user is a member of
            let memberResponse = try await supabaseManager.client
                .from("league_members")
                .select("league_id")
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()

            struct MemberRow: Decodable { let league_id: String }
            let memberRows = try JSONDecoder().decode([MemberRow].self, from: memberResponse.data)
            let leagueIds  = memberRows.map { $0.league_id }

            guard !leagueIds.isEmpty else { myLeagues = []; return }

            // Fetch full league details
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
        guard !newLeagueName.trimmingCharacters(in: .whitespaces).isEmpty else {
            actionMessage = "Enter a league name"; return
        }
        guard let userId = supabaseManager.user?.id else { return }

        let code = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })

        do {
            let response = try await supabaseManager.client
                .from("leagues")
                .insert([
                    "name":       newLeagueName.trimmingCharacters(in: .whitespaces),
                    "invite_code": code,
                    "created_by": userId.uuidString.lowercased(),
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
            actionMessage = "League created! Code: \(code)"
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
            // Find league by invite code
            let leagueResponse = try await supabaseManager.client
                .from("leagues")
                .select("id, name")
                .eq("invite_code", value: code)
                .single()
                .execute()

            struct FoundLeague: Decodable { let id: String; let name: String }
            let league = try JSONDecoder().decode(FoundLeague.self, from: leagueResponse.data)

            // Join
            try await supabaseManager.client
                .from("league_members")
                .insert([
                    "league_id": league.id,
                    "user_id":   userId.uuidString.lowercased(),
                ])
                .execute()

            joinCode = ""
            showJoinLeague = false
            actionMessage = "Joined \(league.name)! 🎉"
            await fetchMyLeagues()
        } catch {
            actionMessage = "Invalid code or already a member"
        }
    }
}
