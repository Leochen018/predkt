import Foundation

struct APIManager {
    static let baseURL = "https://api.predkt.app"

    struct LiveResponse: Codable {
        let liveMatches: [LiveMatchResponse]
        let error: String?
    }

    static func fetchLiveMatches() async throws -> [Match] {
        let url = URL(string: "\(baseURL)/api/live")!
        
        // 1. Fetch the raw data and the response code
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // 2. Check if the server actually sent a "Success" (200) code
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: Status Code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                // If the server failed, print what it said
                let errorText = String(data: data, encoding: .utf8) ?? "No text"
                print("DEBUG: Server Error Message: \(errorText)")
            }
        }

        // 3. Print the raw JSON to the console so you can see it
        if let jsonString = String(data: data, encoding: .utf8) {
            print("DEBUG: Raw JSON from Server: \(jsonString)")
        }

        // 4. Try to decode it
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(LiveResponse.self, from: data)
        return decodedResponse.liveMatches.map { $0.toMatch() }
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
