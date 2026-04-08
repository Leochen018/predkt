import Foundation

struct APIManager {
    static let baseURL = "https://api.predkt.app"

    static func fetchLiveMatches() async throws -> [[String: Any]] {
        let url = URL(string: "\(baseURL)/api/live")!
        let (data, _) = try await URLSession.shared.data(from: url)

        // Print raw JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 API Response: \(jsonString)")
        }

        do {
            // Parse JSON and return raw matches array
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let liveMatches = json["liveMatches"] as? [[String: Any]] else {
                print("⚠️ No liveMatches found in response")
                return []
            }

            print("✅ Parsed \(liveMatches.count) matches")
            return liveMatches
        } catch {
            print("❌ Error fetching matches: \(error)")
            return []
        }
    }

    static func verifyEmail(userId: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/api/verify-email")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["userId": userId, "token": token]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Verification failed", code: -1)
        }
    }
}
