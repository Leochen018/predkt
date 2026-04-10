import Foundation
import Combine

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSubmitting = false
    @Published var lockedAnswers: [Answer] = []

    private var matchesLoaded = false
    private let supabaseManager = SupabaseManager.shared
    private let topLeagueIDs = [39, 140, 135, 78, 61, 94, 88, 2, 3]

    // MARK: - Answer

    struct Answer: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let shortLabel: String
        let probability: Int
        let odds: Double
        let group: String

        var xpValue: Int { max(1, 10 + (100 - probability)) }
        var probabilityDisplay: String { "\(probability)%" }
        var communityPercent: Int { min(95, max(5, probability + Int.random(in: -8...8))) }

        static func == (lhs: Answer, rhs: Answer) -> Bool { lhs.id == rhs.id }

        init(_ label: String, short: String, odds: Double, group: String) {
            self.label       = label
            self.shortLabel  = short
            self.odds        = odds
            self.group       = group
            self.probability = min(99, max(1, Int(round(1.0 / odds * 100))))
        }
    }

    // MARK: - Question

    struct Question: Identifiable {
        let id = UUID()
        let category: String
        let prompt: String
        let icon: String
        let answers: [Answer]
        var isEmpty: Bool { answers.isEmpty }
    }

    // MARK: - Combo

    var totalXP: Int  { lockedAnswers.reduce(0) { $0 + $1.xpValue } }
    var isCombo: Bool { lockedAnswers.count > 1 }

    func lockAnswer(_ answer: Answer) {
        if let idx = lockedAnswers.firstIndex(of: answer) {
            lockedAnswers.remove(at: idx)
        } else {
            lockedAnswers.removeAll { $0.group == answer.group }
            lockedAnswers.append(answer)
        }
    }

    func isLocked(_ answer: Answer) -> Bool    { lockedAnswers.contains(answer) }
    func conflicts(_ answer: Answer) -> Bool   { lockedAnswers.contains { $0.group == answer.group && $0 != answer } }
    func clearAnswers()                        { lockedAnswers = [] }

    // MARK: - Fallback questions (when API has no odds for a match)

    private func fallbackQuestions(for match: Match) -> [Question] {
        [
            Question(
                category: "⚽ MATCH RESULT",
                prompt: "Who wins this match?",
                icon: "trophy",
                answers: [
                    Answer("\(match.home) Win", short: "HOME", odds: 2.10, group: "result"),
                    Answer("Draw",              short: "DRAW", odds: 3.20, group: "result"),
                    Answer("\(match.away) Win", short: "AWAY", odds: 1.90, group: "result"),
                ]
            ),
            Question(
                category: "🥅 HOW MANY GOALS?",
                prompt: "How many goals will be scored?",
                icon: "soccerball",
                answers: [
                    Answer("Fewer than 3 goals", short: "U2.5", odds: 2.00, group: "goals_25"),
                    Answer("3+ goals",            short: "O2.5", odds: 1.80, group: "goals_25"),
                ]
            ),
            Question(
                category: "🔀 BOTH TEAMS SCORE?",
                prompt: "Will both teams get on the scoresheet?",
                icon: "arrow.left.and.right.circle",
                answers: [
                    Answer("Yes — both teams score",  short: "YES", odds: 2.30, group: "btts"),
                    Answer("No — at least one blank", short: "NO",  odds: 1.60, group: "btts"),
                ]
            ),
        ]
    }

    // MARK: - Full Questions from Real Odds

    func getQuestions(for match: Match) -> [Question] {
        let o = match.odds
        var questions: [Question] = []

        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func answers(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }

        let resultAnswers = answers([
            a("\(match.home) Win", short: "HOME", o?.homeWin,  "result"),
            a("Draw",              short: "DRAW", o?.draw,     "result"),
            a("\(match.away) Win", short: "AWAY", o?.awayWin,  "result"),
        ])
        if !resultAnswers.isEmpty { questions.append(Question(category: "⚽ MATCH RESULT", prompt: "Who wins this match?", icon: "trophy", answers: resultAnswers)) }

        let dcAnswers = answers([
            a("\(match.home) or Draw",  short: "1X", o?.homeOrDraw, "dc"),
            a("\(match.away) or Draw",  short: "X2", o?.awayOrDraw, "dc"),
            a("Either team wins",       short: "12", o?.homeOrAway, "dc"),
        ])
        if !dcAnswers.isEmpty { questions.append(Question(category: "🛡 DOUBLE CHANCE", prompt: "Which two outcomes can you cover?", icon: "shield.lefthalf.filled", answers: dcAnswers)) }

        let goalAnswers = answers([
            a("Fewer than 1 goal",  short: "U0.5", o?.under05, "goals_05"),
            a("At least 1 goal",    short: "O0.5", o?.over05,  "goals_05"),
            a("Fewer than 2 goals", short: "U1.5", o?.under15, "goals_15"),
            a("2+ goals",           short: "O1.5", o?.over15,  "goals_15"),
            a("Fewer than 3 goals", short: "U2.5", o?.under25, "goals_25"),
            a("3+ goals",           short: "O2.5", o?.over25,  "goals_25"),
            a("Fewer than 4 goals", short: "U3.5", o?.under35, "goals_35"),
            a("4+ goals",           short: "O3.5", o?.over35,  "goals_35"),
            a("5+ goals",           short: "O4.5", o?.over45,  "goals_45"),
        ])
        if !goalAnswers.isEmpty { questions.append(Question(category: "🥅 HOW MANY GOALS?", prompt: "How many goals will be scored?", icon: "soccerball", answers: goalAnswers)) }

        let htGoalAnswers = answers([
            a("No first-half goals", short: "U0.5", o?.htUnder05, "ht_05"),
            a("1+ first-half goal",  short: "O0.5", o?.htOver05,  "ht_05"),
            a("2+ first-half goals", short: "O1.5", o?.htOver15,  "ht_15"),
        ])
        if !htGoalAnswers.isEmpty { questions.append(Question(category: "⏱ FIRST HALF", prompt: "Goals before half time?", icon: "1.circle", answers: htGoalAnswers)) }

        let bttsAnswers = answers([
            a("Yes — both teams score",  short: "YES", o?.bttsYes, "btts"),
            a("No — at least one blank", short: "NO",  o?.bttsNo,  "btts"),
        ])
        if !bttsAnswers.isEmpty { questions.append(Question(category: "🔀 BOTH TEAMS SCORE?", prompt: "Will both teams get on the scoresheet?", icon: "arrow.left.and.right.circle", answers: bttsAnswers)) }

        let htResultAnswers = answers([
            a("\(match.home) leading", short: "HOME", o?.htHomeWin, "ht_result"),
            a("Level at half time",    short: "DRAW", o?.htDraw,    "ht_result"),
            a("\(match.away) leading", short: "AWAY", o?.htAwayWin, "ht_result"),
        ])
        if !htResultAnswers.isEmpty { questions.append(Question(category: "📊 HALF TIME SCORE", prompt: "Who's leading at half time?", icon: "clock", answers: htResultAnswers)) }

        let cornerAnswers = answers([
            a("Fewer than 8 corners",  short: "U7.5",  o?.cornersUnder75,  "corners_75"),
            a("8+ corners",            short: "O7.5",  o?.cornersOver75,   "corners_75"),
            a("Fewer than 9 corners",  short: "U8.5",  o?.cornersUnder85,  "corners_85"),
            a("9+ corners",            short: "O8.5",  o?.cornersOver85,   "corners_85"),
            a("Fewer than 10 corners", short: "U9.5",  o?.cornersUnder95,  "corners_95"),
            a("10+ corners",           short: "O9.5",  o?.cornersOver95,   "corners_95"),
            a("11+ corners",           short: "O10.5", o?.cornersOver105,  "corners_105"),
        ])
        if !cornerAnswers.isEmpty { questions.append(Question(category: "🚩 CORNERS", prompt: "How many corners in the match?", icon: "flag", answers: cornerAnswers)) }

        let cardAnswers = answers([
            a("Fewer than 2 cards", short: "U1.5", o?.cardsUnder15, "cards_15"),
            a("2+ cards",           short: "O1.5", o?.cardsOver15,  "cards_15"),
            a("Fewer than 3 cards", short: "U2.5", o?.cardsUnder25, "cards_25"),
            a("3+ cards",           short: "O2.5", o?.cardsOver25,  "cards_25"),
            a("4+ cards",           short: "O3.5", o?.cardsOver35,  "cards_35"),
        ])
        if !cardAnswers.isEmpty { questions.append(Question(category: "🟨 BOOKINGS", prompt: "How many yellow cards will be shown?", icon: "rectangle.portrait", answers: cardAnswers)) }

        let csAnswers = answers([
            a("\(match.home) keep a clean sheet", short: "HOME", o?.homeCleanSheet, "cs_home"),
            a("\(match.away) keep a clean sheet", short: "AWAY", o?.awayCleanSheet, "cs_away"),
        ])
        if !csAnswers.isEmpty { questions.append(Question(category: "🔒 SHUTOUT", prompt: "Will a team keep a clean sheet?", icon: "lock.shield", answers: csAnswers)) }

        func playerAnswers(_ players: [PlayerOdd]?, group: String) -> [Answer] {
            (players ?? []).compactMap { p in
                guard p.odd > 1.0 else { return nil }
                return Answer(p.name, short: "⚽", odds: p.odd, group: "\(group)_\(p.name)")
            }
        }

        let anytime = playerAnswers(o?.playerAnytime, group: "anytime")
        if !anytime.isEmpty { questions.append(Question(category: "⚽ GOALSCORER", prompt: "Who scores at any point?", icon: "person.fill.checkmark", answers: anytime)) }

        let firstGoal = playerAnswers(o?.playerFirstGoal, group: "first")
        if !firstGoal.isEmpty { questions.append(Question(category: "🥇 FIRST GOAL", prompt: "Who scores first?", icon: "1.circle.fill", answers: firstGoal)) }

        let carded = playerAnswers(o?.playerToBeCarded, group: "card")
        if !carded.isEmpty { questions.append(Question(category: "🟨 WHO GETS BOOKED?", prompt: "Which player picks up a card?", icon: "rectangle.portrait.fill", answers: carded)) }

        // ✅ If API returned no odds at all, show fallback questions so match is never empty
        return questions.isEmpty ? fallbackQuestions(for: match) : questions
    }

    // MARK: - Filtered Matches

    private func parseDate(_ raw: String) -> Date {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw) ?? Date()
    }

    var filteredMatches: [Match] {
        let cal = Calendar.current
        return matches
            .filter { topLeagueIDs.contains($0.leagueId) && cal.isDate(parseDate($0.rawDate), inSameDayAs: selectedDate) }
            .sorted { m1, m2 in m1.isLive != m2.isLive ? m1.isLive : m1.rawDate < m2.rawDate }
    }

    // MARK: - Load

    func loadMatches() async {
        guard !matchesLoaded else { return }
        isLoading = true; errorMessage = nil
        do {
            matches = try await APIManager.fetchAllMatches()
            matchesLoaded = true
            print("✅ Loaded \(matches.count) matches")
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func refreshMatches() async { matchesLoaded = false; await loadMatches() }

    // MARK: - Submit

    func submitPlays(match: Match, myPicksCount: Int) async -> Bool {
        guard !lockedAnswers.isEmpty else { errorMessage = "Lock in at least one answer"; return false }
        guard myPicksCount + lockedAnswers.count <= 5 else { errorMessage = "Max 5 plays per day"; return false }

        isSubmitting = true; errorMessage = nil
        let comboId = isCombo ? UUID().uuidString : nil

        do {
            for answer in lockedAnswers {
                try await supabaseManager.createPick(
                    match: match.displayName, market: answer.label,
                    odds: answer.odds, probability: answer.probability,
                    pointsPossible: answer.xpValue, pointsLost: max(1, answer.xpValue / 2),
                    comboId: comboId
                )
            }
            clearAnswers()
            isSubmitting = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
            return false
        }
    }
}
