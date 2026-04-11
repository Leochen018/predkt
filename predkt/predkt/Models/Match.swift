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
    // ID 1 — Match Winner
    let homeWin: Double?; let draw: Double?; let awayWin: Double?
    // ID 2 — Home/Away (no draw)
    let homeWinNoDraw: Double?; let awayWinNoDraw: Double?
    // ID 3 — Both Teams Score
    let bttsYes: Double?; let bttsNo: Double?
    // ID 4 — Goals Over/Under
    let over05: Double?; let under05: Double?
    let over15: Double?; let under15: Double?
    let over25: Double?; let under25: Double?
    let over35: Double?; let under35: Double?
    let over45: Double?; let under45: Double?
    // ID 5 — Goals Odd/Even
    let goalsOdd: Double?; let goalsEven: Double?
    // ID 6 — Home Team Goals
    let homeOver05: Double?; let homeUnder05: Double?
    let homeOver15: Double?; let homeUnder15: Double?
    let homeOver25: Double?; let homeUnder25: Double?
    // ID 7 — Away Team Goals
    let awayOver05: Double?; let awayUnder05: Double?
    let awayOver15: Double?; let awayUnder15: Double?
    let awayOver25: Double?; let awayUnder25: Double?
    // ID 8 — BTTS First Half
    let bttsFirstHalf: Double?
    // ID 9 — BTTS Second Half
    let bttsSecondHalf: Double?
    // ID 10 — First Half Winner
    let htHomeWin: Double?; let htDraw: Double?; let htAwayWin: Double?
    // ID 11 — Second Half Winner
    let shHomeWin: Double?; let shDraw: Double?; let shAwayWin: Double?
    // ID 12 — Double Chance
    let homeOrDraw: Double?; let awayOrDraw: Double?; let homeOrAway: Double?
    // ID 13 — Draw No Bet
    let dnbHome: Double?; let dnbAway: Double?
    // ID 14 — First Team to Score
    let firstTeamHome: Double?; let firstTeamAway: Double?; let firstTeamNone: Double?
    // ID 15 — Last Team to Score
    let lastTeamHome: Double?; let lastTeamAway: Double?
    // ID 16 — Correct Score FT
    let correctScores: [CorrectScoreOdd]?
    // ID 17 — Asian Handicap
    let ahHome05: Double?; let ahAway05: Double?
    let ahHome15: Double?; let ahAway15: Double?
    // ID 18 — Win to Nil
    let homeWinToNil: Double?; let awayWinToNil: Double?
    // ID 19 — BTTS & Winner
    let bttsAndHomeWin: Double?; let bttsAndDraw: Double?; let bttsAndAwayWin: Double?
    // ID 20 — Exact Goals
    let exactGoals0: Double?; let exactGoals1: Double?; let exactGoals2: Double?
    let exactGoals3: Double?; let exactGoals4: Double?; let exactGoals5plus: Double?
    // ID 21 — Clean Sheet
    let homeCleanSheet: Double?; let awayCleanSheet: Double?
    // ID 22 — HT/FT
    let htftHomeHome: Double?; let htftDrawHome: Double?; let htftAwayHome: Double?
    let htftHomeDraw: Double?; let htftDrawDraw: Double?; let htftAwayDraw: Double?
    let htftHomeAway: Double?; let htftDrawAway: Double?; let htftAwayAway: Double?
    // ID 23 — Corners
    let cornersOver75: Double?; let cornersUnder75: Double?
    let cornersOver85: Double?; let cornersUnder85: Double?
    let cornersOver95: Double?; let cornersUnder95: Double?
    let cornersOver105: Double?; let cornersUnder105: Double?
    // ID 24 — BTTS Both Halves
    let bttsBothHalves: Double?
    // ID 25 — Total Shots
    let shotsOver85: Double?; let shotsUnder85: Double?
    let shotsOver105: Double?; let shotsUnder105: Double?
    let shotsOver125: Double?; let shotsUnder125: Double?
    // ID 26-32 — Player Props
    let playerFirstGoal: [PlayerOdd]?
    let playerLastGoal: [PlayerOdd]?
    let playerAnytime: [PlayerOdd]?
    let playerToBeCarded: [PlayerOdd]?
    let playerToAssist: [PlayerOdd]?
    let playerShotsOnTarget: [PlayerOdd]?
    let playerToBeFouled: [PlayerOdd]?
    let playerToBeScored2: [PlayerOdd]?
    let playerHatTrick: [PlayerOdd]?
    // ID 33 — Score in Both Halves
    let homeScoreBothHalves: Double?; let awayScoreBothHalves: Double?
    // ID 34 — Home Goals Odd/Even
    let homeGoalsOdd: Double?; let homeGoalsEven: Double?
    // ID 35 — Away Goals Odd/Even
    let awayGoalsOdd: Double?; let awayGoalsEven: Double?
    // ID 37 — Winning Margin
    let winMarginHome1: Double?; let winMarginHome2: Double?; let winMarginHome3: Double?
    let winMarginAway1: Double?; let winMarginAway2: Double?; let winMarginAway3: Double?
    let winMarginDraw: Double?
    // ID 45 — Correct Score First Half
    let correctScoresHT: [CorrectScoreOdd]?
    // ID 62 — Correct Score Second Half
    let correctScoresSH: [CorrectScoreOdd]?
    // First Half Goals (legacy)
    let htOver05: Double?; let htUnder05: Double?
    let htOver15: Double?; let htUnder15: Double?
    // First Half Corners
    let htCornersOver35: Double?; let htCornersUnder35: Double?
    let htCornersOver45: Double?; let htCornersUnder45: Double?
    // Cards
    let cardsOver15: Double?; let cardsUnder15: Double?
    let cardsOver25: Double?; let cardsUnder25: Double?
    let cardsOver35: Double?; let cardsUnder35: Double?
    let cardsOver45: Double?; let cardsUnder45: Double?
    // Offsides
    let offsidesOver15: Double?; let offsidesUnder15: Double?
    let offsidesOver25: Double?; let offsidesUnder25: Double?
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
        guard let d = parsedDate else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current; return f.string(from: d)
    }
    var matchDate: String {
        guard let d = parsedDate else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.timeZone = .current; return f.string(from: d)
    }
}

