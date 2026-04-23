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
   
    let result: String          // "pending", "correct", "wrong"
    let points_earned: Int?     // set when resolved
    let streak_multiplier: Double?
    let points_before_multiplier: Int?
    let created_at: String
    let username: String?
    let profiles: Profile?
    let combo_id: String?
    let probability: Int?

    enum CodingKeys: String, CodingKey {
        case id, user_id, match, market, confidence, odds, difficulty
        case difficulty_multiplier, points_possible, result
        case points_earned, streak_multiplier, points_before_multiplier
        case created_at, username, profiles, combo_id, probability
    }

    var resultColor: String {
        switch result {
        case "correct": return "#C8FF57"
        case "wrong":   return "#FF5C5C"
        default:        return "#8B8FA8"
        }
    }

    var resultIcon: String {
        switch result {
        case "correct": return "✓"
        case "wrong":   return "✗"
        default:        return "⏱"
        }
    }
}

struct Profile: Identifiable, Codable {
    let id: String
    let username: String
}
