import Foundation

struct Match: Identifiable, Codable {
    let id: String
    let home: String
    let away: String
    let status: String
    let elapsed: Int?
    let homeGoals: Int
    let awayGoals: Int
    let competition: String
    let isLive: Bool
    let isFinished: Bool
    let rawDate: String
    let leagueId: Int
    
    var displayName: String { "\(home) vs \(away)" }
    var score: String { "\(homeGoals) - \(awayGoals)" }
}

struct LiveMatchResponse: Codable {
    let fixtureId: Int
    let home: String
    let away: String
    let status: String
    let elapsed: Int?
    let homeGoals: Int?
    let awayGoals: Int?
    let competition: String
    let isLive: Bool
    let isFinished: Bool
    let date: String? // Optional string to prevent "missing key" errors
    let league_id: Int?

    enum CodingKeys: String, CodingKey {
        case fixtureId, home, away, status, elapsed, homeGoals, awayGoals, competition, isLive, isFinished, date
        case league_id
    }

    func toMatch() -> Match {
        // Fallback if date is missing or malformed
        let fallbackDate = ISO8601DateFormatter().string(from: Date())
        
        return Match(
            id: String(fixtureId),
            home: home,
            away: away,
            status: status,
            elapsed: elapsed,
            homeGoals: homeGoals ?? 0,
            awayGoals: awayGoals ?? 0,
            competition: competition,
            isLive: isLive,
            isFinished: isFinished,
            rawDate: date ?? fallbackDate,
            leagueId: league_id ?? 0 
        )
    }
}
