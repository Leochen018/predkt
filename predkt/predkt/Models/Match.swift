import Foundation

struct Match: Identifiable {
    let id: String // fixtureId
    let home: String
    let away: String
    let status: String
    let elapsed: Int?
    let homeGoals: Int
    let awayGoals: Int
    let competition: String
    let isLive: Bool
    let isFinished: Bool

    var displayName: String {
        "\(home) vs \(away)"
    }

    var score: String {
        "\(homeGoals) - \(awayGoals)"
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

    enum CodingKeys: String, CodingKey {
        case fixtureId, home, away, status, elapsed, homeGoals, awayGoals, competition, isLive, isFinished
    }

    func toMatch() -> Match {
        Match(
            id: String(fixtureId),
            home: home,
            away: away,
            status: status,
            elapsed: elapsed,
            homeGoals: homeGoals ?? 0,
            awayGoals: awayGoals ?? 0,
            competition: competition,
            isLive: isLive,
            isFinished: isFinished
        )
    }
}
