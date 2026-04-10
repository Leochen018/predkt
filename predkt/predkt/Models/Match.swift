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
    let homeLogo: String?   // ✅ NEW: team badge URL
    let awayLogo: String?   // ✅ NEW: team badge URL

    var displayName: String { "\(home) vs \(away)" }
    var score: String { "\(homeGoals) - \(awayGoals)" }

    // Formatted kick-off time in local timezone e.g. "20:45"
    var kickoffTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: rawDate) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "HH:mm"
        display.timeZone = .current
        return display.string(from: date)
    }
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
    let date: String?
    let league_id: Int?
    let homeLogo: String?   // ✅ NEW
    let awayLogo: String?   // ✅ NEW

    func toMatch() -> Match {
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
            leagueId: league_id ?? 0,
            homeLogo: homeLogo,
            awayLogo: awayLogo
        )
    }
}
