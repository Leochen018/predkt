import Foundation

struct Pick: Identifiable, Codable {
    let id: String
    let user_id: String
    let match: String
    let market: String
    let confidence: Int
    let odds: Double
    let difficulty: String?
    let difficulty_multiplier: Double?
    let points_possible: Int
    let points_lost: Int
    let result: String // "pending", "correct", "wrong"
    let points_earned: Int?
    let streak_multiplier: Double?
    let points_before_multiplier: Int?
    let created_at: String
    let username: String? // joined from profiles
    let profiles: Profile?

    enum CodingKeys: String, CodingKey {
        case id, user_id, match, market, confidence, odds, difficulty
        case difficulty_multiplier, points_possible, points_lost, result
        case points_earned, streak_multiplier, points_before_multiplier, created_at
        case username, profiles
    }

    var resultColor: String {
        switch result {
        case "correct": return "#22c55e"
        case "wrong": return "#ef4444"
        default: return "#4a4958"
        }
    }

    var resultIcon: String {
        switch result {
        case "correct": return "✓"
        case "wrong": return "✗"
        default: return "⏱"
        }
    }
}

struct Profile: Identifiable, Codable {
    let id: String
    let username: String
}
