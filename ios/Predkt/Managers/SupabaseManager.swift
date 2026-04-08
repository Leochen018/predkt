import Foundation
import Supabase
import Combine

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
            supabaseKey: supabaseKey
        )
        bootstrapAsync()

        // Listen to auth state changes
        Task {
            for await state in await client.auth.authStatePublisher.values {
                DispatchQueue.main.async {
                    self.user = state.session?.user
                    self.session = state.session
                    print("🔐 Auth state changed: user = \(self.user?.id ?? "nil")")
                }
            }
        }
    }

    private func bootstrapAsync() {
        Task {
            do {
                let session = try await client.auth.session
                DispatchQueue.main.async {
                    self.session = session
                    self.user = session.user
                }
            } catch {
                print("Failed to get session: \(error)")
            }
        }
    }

    func login(email: String, password: String) async throws {
        let response = try await client.auth.signIn(email: email, password: password)
        DispatchQueue.main.async {
            self.session = response
            self.user = response.user
        }
    }

    func signup(email: String, password: String, username: String) async throws {
        // Call backend API instead of direct Supabase signup
        let url = URL(string: "https://api.predkt.app/api/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "password": password,
            "username": username
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Signup failed", code: -1)
        }
    }

    func logout() async throws {
        print("🔐 SupabaseManager: Starting logout...")
        try await client.auth.signOut()
        print("🔐 SupabaseManager: Cleared session from Supabase")

        DispatchQueue.main.async {
            print("🔐 SupabaseManager: Clearing @Published properties")
            self.session = nil
            self.user = nil
            print("✅ SupabaseManager: Logout complete - session and user cleared")
        }
    }

    func getAccessToken() -> String? {
        session?.accessToken
    }

    func fetchFeed() async throws -> [Pick] {
        let response = try await client
            .from("picks")
            .select("*, profiles(username, id)")
            .order("created_at", ascending: false)
            .limit(20)
            .execute()

        let data = response.data
        let picks = try JSONDecoder().decode([Pick].self, from: data)
        return picks
    }

    func fetchMyPicks() async throws -> [Pick] {
        guard let userId = user?.id else { throw NSError(domain: "No user", code: -1) }

        let today = Calendar.current.startOfDay(for: Date()).toISO8601String()

        let response = try await client
            .from("picks")
            .select("*")
            .eq("user_id", value: userId)
            .gte("created_at", value: today)
            .order("created_at", ascending: false)
            .execute()

        let picks = try JSONDecoder().decode([Pick].self, from: response.data)
        return picks
    }

    func fetchUserProfile() async throws -> UserProfile? {
        guard let userId = user?.id else { return nil }

        let response = try await client
            .from("profiles")
            .select("*")
            .eq("id", value: userId)
            .single()
            .execute()

        let profile = try JSONDecoder().decode(UserProfile.self, from: response.data)
        return profile
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

        let pick: [String: Any] = [
            "user_id": userId,
            "match": match,
            "market": market,
            "confidence": confidence,
            "odds": odds,
            "difficulty": difficulty,
            "difficulty_multiplier": difficulty_multiplier,
            "points_possible": points_possible,
            "points_lost": points_lost,
            "result": "pending"
        ]

        try await client
            .from("picks")
            .insert(pick)
            .execute()
    }
}

extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
