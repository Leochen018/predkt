import Foundation

struct PlayerOdd: Codable, Identifiable {
    var id: String { name }
    let name: String
    let odd: Double
}

struct CorrectScoreOdd: Codable, Identifiable {
    var id: String { score }
    let score: String
    let odd: Double
}

struct MatchOdds: Codable {
    let homeWin: Double?; let draw: Double?; let awayWin: Double?
    let homeOrDraw: Double?; let awayOrDraw: Double?; let homeOrAway: Double?
    let dnbHome: Double?; let dnbAway: Double?
    let over05: Double?; let under05: Double?
    let over15: Double?; let under15: Double?
    let over25: Double?; let under25: Double?
    let over35: Double?; let under35: Double?
    let over45: Double?; let under45: Double?
    let htOver05: Double?; let htUnder05: Double?
    let htOver15: Double?; let htUnder15: Double?
    let bttsYes: Double?; let bttsNo: Double?
    let htHomeWin: Double?; let htDraw: Double?; let htAwayWin: Double?
    let cornersOver75: Double?; let cornersUnder75: Double?
    let cornersOver85: Double?; let cornersUnder85: Double?
    let cornersOver95: Double?; let cornersUnder95: Double?
    let cornersOver105: Double?; let cornersUnder105: Double?
    let cardsOver15: Double?; let cardsUnder15: Double?
    let cardsOver25: Double?; let cardsUnder25: Double?
    let cardsOver35: Double?; let cardsUnder35: Double?
    let homeCleanSheet: Double?; let awayCleanSheet: Double?
    let homeWinToNil: Double?; let awayWinToNil: Double?
    let correctScores: [CorrectScoreOdd]?
    let playerFirstGoal: [PlayerOdd]?
    let playerLastGoal: [PlayerOdd]?
    let playerAnytime: [PlayerOdd]?
    let playerToBeCarded: [PlayerOdd]?
    let playerToAssist: [PlayerOdd]?
}

struct Match: Identifiable, Codable {
    let id: String
    let home: String; let away: String
    let status: String; let elapsed: Int?
    let homeGoals: Int; let awayGoals: Int
    let competition: String
    let isLive: Bool; let isFinished: Bool
    let rawDate: String; let leagueId: Int
    let homeLogo: String?; let awayLogo: String?
    let odds: MatchOdds?
    let venue: String?

    var displayName: String { "\(home) vs \(away)" }
    var score: String       { "\(homeGoals) - \(awayGoals)" }

    private var parsedDate: Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: rawDate) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: rawDate)
    }

    var kickoffTime: String {
        guard let date = parsedDate else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
        return f.string(from: date)
    }

    var matchDate: String {
        guard let date = parsedDate else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.timeZone = .current
        return f.string(from: date)
    }
}

struct LiveMatchResponse: Codable {
    let fixtureId: Int
    let home: String; let away: String
    let status: String; let elapsed: Int?
    let homeGoals: Int?; let awayGoals: Int?
    let competition: String
    let isLive: Bool; let isFinished: Bool
    let date: String?; let league_id: Int?
    let homeLogo: String?; let awayLogo: String?
    let odds: MatchOdds?
    let venue: String?

    func toMatch() -> Match {
        Match(
            id: String(fixtureId), home: home, away: away, status: status,
            elapsed: elapsed, homeGoals: homeGoals ?? 0, awayGoals: awayGoals ?? 0,
            competition: competition, isLive: isLive, isFinished: isFinished,
            rawDate: date ?? ISO8601DateFormatter().string(from: Date()),
            leagueId: league_id ?? 0, homeLogo: homeLogo, awayLogo: awayLogo,
            odds: odds, venue: venue
        )
    }
}
