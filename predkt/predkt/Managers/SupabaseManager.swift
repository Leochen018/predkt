import Foundation
import Supabase
import Combine

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    @Published var session: Session?
    @Published var user: User?

    private let supabaseURL = "https://iffpxhemvquxgstcmnff.supabase.co"
    // Note: In a production app, move this key to a secure .plist or environment variable
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmZnB4aGVtdnF1eGdzdGNtbmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4NzY4NzAsImV4cCI6MjA5MDQ1Mjg3MH0.LshccWh0u1bLhu2XJVpEAeD2DtLfeUMn0QO2MF27ITg"

    private(set) var client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey
        )
        bootstrapAsync()
    }

    private func bootstrapAsync() {
        Task {
            do {
                // Latest Supabase-Swift uses 'session' property for current auth state
                let currentSession = try await client.auth.session
                self.session = currentSession
                self.user = currentSession.user
            } catch {
                print("No active session found: \(error.localizedDescription)")
            }
        }
    }

    func login(email: String, password: String) async throws {
        // Updated: signIn returns a Session directly in modern versions
        let response = try await client.auth.signIn(email: email, password: password)
        self.session = response
        self.user = response.user
    }

    func signup(email: String, password: String, username: String) async throws {
        let url = URL(string: "https://api.predkt.app/api/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "email": email,
            "password": password,
            "username": username
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "Signup failed", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned an error during signup."])
        }
    }

    func logout() async throws {
        try await client.auth.signOut()
        self.session = nil
        self.user = nil
    }

    func getAccessToken() -> String? {
        session?.accessToken
    }

    func fetchFeed() async throws -> [Pick] {
        // Modern Supabase-Swift handles decoding directly via .execute().value
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

        return try await client
            .from("profiles")
            .select("*")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    func createPick(
        match: String,
        market: String,
        confidence: Int,
        odds: Double,
        difficulty: String,
        difficulty_multiplier: Double,
        points_possible: Int,
        points_lost: Int
    ) async throws {
        guard let userId = user?.id else { throw NSError(domain: "No user", code: -1) }

        // Use AnyJSON or a dedicated Pick struct to avoid [String: Any] casting issues
        let pick: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "match": .string(match),
            "market": .string(market),
            "confidence": .integer(confidence),
            "odds": .double(odds),
            "difficulty": .string(difficulty),
            "difficulty_multiplier": .double(difficulty_multiplier),
            "points_possible": .integer(points_possible),
            "points_lost": .integer(points_lost),
            "result": .string("pending")
        ]

        try await client
            .from("picks")
            .insert(pick)
            .execute()
    }
}

// Helper for date filtering
extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
