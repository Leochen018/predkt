import Foundation

// Player odd entry (for goalscorer, carded, assist markets)
struct PlayerOdd: Codable, Identifiable {
    var id: String { name }
    let name: String
    let odd: Double
}

struct MatchOdds: Codable {
    // Match Result
    let homeWin: Double?
    let draw: Double?
    let awayWin: Double?

    // Double Chance
    let homeOrDraw: Double?
    let awayOrDraw: Double?
    let homeOrAway: Double?

    // Draw No Bet
    let dnbHome: Double?
    let dnbAway: Double?

    // Goals Over/Under
    let over05: Double?;  let under05: Double?
    let over15: Double?;  let under15: Double?
    let over25: Double?;  let under25: Double?
    let over35: Double?;  let under35: Double?
    let over45: Double?;  let under45: Double?

    // HT Goals
    let htOver05: Double?;  let htUnder05: Double?
    let htOver15: Double?;  let htUnder15: Double?

    // BTTS
    let bttsYes: Double?
    let bttsNo: Double?

    // HT Result
    let htHomeWin: Double?
    let htDraw: Double?
    let htAwayWin: Double?

    // Corners
    let cornersOver75: Double?;  let cornersUnder75: Double?
    let cornersOver85: Double?;  let cornersUnder85: Double?
    let cornersOver95: Double?;  let cornersUnder95: Double?
    let cornersOver105: Double?; let cornersUnder105: Double?

    // Cards
    let cardsOver15: Double?;  let cardsUnder15: Double?
    let cardsOver25: Double?;  let cardsUnder25: Double?
    let cardsOver35: Double?;  let cardsUnder35: Double?

    // Clean Sheets
    let homeCleanSheet: Double?
    let awayCleanSheet: Double?

    // Player Props
    let playerFirstGoal: [PlayerOdd]?
    let playerLastGoal: [PlayerOdd]?
    let playerAnytime: [PlayerOdd]?
    let playerToBeCarded: [PlayerOdd]?
    let playerToAssist: [PlayerOdd]?
}

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
    let homeLogo: String?
    let awayLogo: String?
    let odds: MatchOdds?

    var displayName: String { "\(home) vs \(away)" }
    var score: String { "\(homeGoals) - \(awayGoals)" }

    var kickoffTime: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: rawDate) else { return "" }
        let d = DateFormatter()
        d.dateFormat = "HH:mm"
        d.timeZone = .current
        return d.string(from: date)
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
    let homeLogo: String?
    let awayLogo: String?
    let odds: MatchOdds?

    func toMatch() -> Match {
        let fallback = ISO8601DateFormatter().string(from: Date())
        return Match(
            id: String(fixtureId),
            home: home, away: away, status: status,
            elapsed: elapsed,
            homeGoals: homeGoals ?? 0, awayGoals: awayGoals ?? 0,
            competition: competition,
            isLive: isLive, isFinished: isFinished,
            rawDate: date ?? fallback,
            leagueId: league_id ?? 0,
            homeLogo: homeLogo, awayLogo: awayLogo,
            odds: odds
        )
    }
}
