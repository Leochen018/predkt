import Foundation

struct APIManager {
    static let baseURL = "https://api.predkt.app"

    // 1. Updated to match the nested structure of API-Football
    struct LiveResponse: Codable {
        let liveMatches: [LiveMatchResponse]
    }

    static func fetchLiveMatches() async throws -> [Match] {
        let urlString = "\(baseURL)/api/live"
        print("DEBUG: Attempting to fetch from: \(urlString)") // Check the URL
        
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        // Use a simpler data fetch to ensure we see the result even if it's weird
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // FORCE PRINT: This bypasses any decoding logic
        print("--- RAW DATA RECEIVED: \(data.count) bytes ---")
        if let str = String(data: data, encoding: .utf8) {
            print("DEBUG_JSON_BODY: \(str)")
        }
        
        // Now check the response code
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: HTTP Status Code: \(httpResponse.statusCode)")
        }
        
        // The app likely crashes right here:
        let decodedResponse = try JSONDecoder().decode(LiveResponse.self, from: data)
        return decodedResponse.liveMatches.map { $0.toMatch() }
    }
    // 3. Updated to fetch all matches for the calendar
    static func fetchAllMatches() async throws -> [Match] {
        guard let url = URL(string: "\(baseURL)/api/matches") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decodedResponse = try JSONDecoder().decode(LiveResponse.self, from: data)
        return decodedResponse.liveMatches.map { $0.toMatch() }
    }

    static func verifyEmail(userId: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/verify-email") else {
            throw URLError(.badURL)
        }
        
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
