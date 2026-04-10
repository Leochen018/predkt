import Foundation
import Supabase
import Combine

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    @Published var session: Session?
    @Published var user: User?
    
    private let supabaseURL = "https://iffpxhemvquxgstcmnff.supabase.co"
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmZnB4aGVtdnF1eGdzdGNtbmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4NzY4NzAsImV4cCI6MjA5MDQ1Mjg3MH0.LshccWh0u1bLhu2XJVpEAeD2DtLfeUMn0QO2MF27ITg"
    
    private(set) var client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: .init(
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        listenToAuthChanges()
        bootstrapAsync()
    }
    
    private func listenToAuthChanges() {
        Task {
            for await (event, session) in client.auth.authStateChanges {
                self.session = session
                self.user = session?.user
                print("🔔 Auth Event: \(event)")
            }
        }
    }
    
    private func bootstrapAsync() {
        Task {
            do {
                let currentSession = try await client.auth.session
                self.session = currentSession
                self.user = currentSession.user
                print("✅ Session Loaded: \(currentSession.user.email ?? "Unknown User")")
            } catch {
                print("ℹ️ No active session: \(error.localizedDescription)")
            }
        }
    }
    
    func login(email: String, password: String) async throws {
        let response = try await client.auth.signIn(email: email, password: password)
        self.session = response
        self.user = response.user
    }
    
    func signup(email: String, password: String, username: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["username": .string(username)]
        )
    }
    
    func verifyCode(email: String, code: String) async throws {
        let response = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .signup
        )
        self.session = response.session
        self.user = response.user
    }
    
    func logout() async throws {
        try await client.auth.signOut()
        self.session = nil
        self.user = nil
    }
    
    func getAccessToken() -> String? {
        session?.accessToken
    }
    
    // MARK: - Data Fetching
    
    func fetchFeed() async throws -> [Pick] {
        return try await client
            .from("picks")
            .select("*, profiles(username, id)")
            .order("created_at", ascending: false)
            .limit(20)
            .execute()
            .value
    }
    
    func fetchMyPicks() async throws -> [Pick] {
        guard let userId = user?.id else { throw NSError(domain: "No user", code: -1) }
        let today = Calendar.current.startOfDay(for: Date()).toISO8601String()
        
        return try await client
            .from("picks")
            .select("*")
            .eq("user_id", value: userId)
            .gte("created_at", value: today)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    func fetchUserProfile() async throws -> UserProfile? {
        guard let userId = user?.id else { return nil }
        
        let response = try await client
            .from("profiles")
            .select("*")
            .eq("id", value: userId)
            .execute()
        
        let profiles = try JSONDecoder().decode([UserProfile].self, from: response.data)
        return profiles.first
    }
    
    // MARK: - Update Username
    
    func updateUsername(_ newUsername: String) async throws {
        guard let userId = user?.id else { throw NSError(domain: "No user", code: -1) }
        
        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Username cannot be empty", code: -1)
        }
        guard trimmed.count >= 3 else {
            throw NSError(domain: "Username must be at least 3 characters", code: -1)
        }
        
        try await client
            .from("profiles")
            .update(["username": trimmed])
            .eq("id", value: userId.uuidString.lowercased())
            .execute()
    }
    
    // MARK: - Create Pick
    
    
    func createPick(
        match: String,
        market: String,
        odds: Double,
        probability: Int,
        pointsPossible: Int,
        pointsLost: Int,
        comboId: String? = nil
    ) async throws {
        guard let userId = user?.id else { throw NSError(domain: "No user", code: -1) }
        
        var pick: [String: AnyJSON] = [
            "user_id":          .string(userId.uuidString.lowercased()),
            "match":            .string(match),
            "market":           .string(market),
            "odds":             .double(odds),
            "probability":      .integer(probability),
            "points_possible":  .integer(pointsPossible),
            "points_lost":      .integer(pointsLost),
            "result":           .string("pending"),
            // Legacy fields kept for backwards compatibility
            "confidence":       .integer(probability),
            "difficulty":       .string("standard"),
            "difficulty_multiplier": .double(1.0),
        ]
        
        if let comboId {
            pick["combo_id"] = .string(comboId)
        }
        
        try await client
            .from("picks")
            .insert(pick)
            .execute()
    }
    
    extension Date {
        func toISO8601String() -> String {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: self)
        }
    }
}
