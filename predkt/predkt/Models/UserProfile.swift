import Foundation

struct UserProfile: Codable {
    let id: String
    let email: String?
    let username: String
    let display_name: String?
    let is_anonymous: Bool?
    let current_streak: Int?
    let best_streak: Int?
    let weekly_points: Int?
    let total_points: Int?
    let daily_streak: Int?
    let best_daily_streak: Int?
    let last_pick_date: String?
    let created_at: String?
    let favourite_team: String?    // ✅ comma-separated team names e.g. "Arsenal,Liverpool"
    let favourite_league: String?  // ✅ comma-separated league IDs e.g. "39,140,2"
}
