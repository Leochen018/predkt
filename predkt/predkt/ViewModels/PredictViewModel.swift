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
    private let topLeagueIDs = [39,140,135,78,61,94,88,2,3,848,45,48,143,137,529,66,4,32]

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
            self.label = label; self.shortLabel = short; self.odds = odds; self.group = group
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
        if let idx = lockedAnswers.firstIndex(of: answer) { lockedAnswers.remove(at: idx) }
        else { lockedAnswers.removeAll { $0.group == answer.group }; lockedAnswers.append(answer) }
    }
    func isLocked(_ answer: Answer) -> Bool    { lockedAnswers.contains(answer) }
    func conflicts(_ answer: Answer) -> Bool   { lockedAnswers.contains { $0.group == answer.group && $0 != answer } }
    func clearAnswers()                        { lockedAnswers = [] }

    // MARK: - Fallback (always shows something)

    private func fallbackQuestions(for match: Match) -> [Question] {[
        Question(category: "⚽ MATCH RESULT", prompt: "Who wins this match?", icon: "trophy", answers: [
            Answer("\(match.home) Win", short: "HOME", odds: 2.10, group: "result"),
            Answer("Draw",              short: "DRAW", odds: 3.20, group: "result"),
            Answer("\(match.away) Win", short: "AWAY", odds: 1.90, group: "result"),
        ]),
        Question(category: "🛡 DOUBLE CHANCE", prompt: "Which two outcomes can you cover?", icon: "shield.lefthalf.filled", answers: [
            Answer("\(match.home) or Draw", short: "1X", odds: 1.35, group: "dc"),
            Answer("Either team wins",      short: "12", odds: 1.25, group: "dc"),
            Answer("\(match.away) or Draw", short: "X2", odds: 1.40, group: "dc"),
        ]),
        Question(category: "🥅 HOW MANY GOALS?", prompt: "How many goals will be scored?", icon: "soccerball", answers: [
            Answer("Fewer than 3 goals", short: "U2.5", odds: 2.00, group: "goals_25"),
            Answer("3+ goals",           short: "O2.5", odds: 1.80, group: "goals_25"),
        ]),
        Question(category: "🔀 BOTH TEAMS SCORE?", prompt: "Will both teams get on the scoresheet?", icon: "arrow.left.and.right.circle", answers: [
            Answer("Yes — both teams score",  short: "YES", odds: 2.30, group: "btts"),
            Answer("No — at least one blank", short: "NO",  odds: 1.60, group: "btts"),
        ]),
        Question(category: "📊 HALF TIME SCORE", prompt: "Who's leading at half time?", icon: "clock", answers: [
            Answer("\(match.home) leading", short: "HOME", odds: 2.60, group: "ht_result"),
            Answer("Level at half time",    short: "DRAW", odds: 2.10, group: "ht_result"),
            Answer("\(match.away) leading", short: "AWAY", odds: 3.50, group: "ht_result"),
        ]),
    ]}

    // MARK: - Full Questions

    func getQuestions(for match: Match) -> [Question] {
        let o = match.odds
        var questions: [Question] = []

        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func answers(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }

        // 1. Match Result
        let r = answers([a("\(match.home) Win",short:"HOME",o?.homeWin,"result"),a("Draw",short:"DRAW",o?.draw,"result"),a("\(match.away) Win",short:"AWAY",o?.awayWin,"result")])
        if !r.isEmpty { questions.append(Question(category:"⚽ MATCH RESULT",prompt:"Who wins this match?",icon:"trophy",answers:r)) }

        // 2. Double Chance
        let dc = answers([a("\(match.home) or Draw",short:"1X",o?.homeOrDraw,"dc"),a("Either team wins",short:"12",o?.homeOrAway,"dc"),a("\(match.away) or Draw",short:"X2",o?.awayOrDraw,"dc")])
        if !dc.isEmpty { questions.append(Question(category:"🛡 DOUBLE CHANCE",prompt:"Which two outcomes can you cover?",icon:"shield.lefthalf.filled",answers:dc)) }

        // 3. Draw No Bet
        let dnb = answers([a(match.home,short:"HOME",o?.dnbHome,"dnb"),a(match.away,short:"AWAY",o?.dnbAway,"dnb")])
        if !dnb.isEmpty { questions.append(Question(category:"🔄 DRAW NO BET",prompt:"Pick a winner — draw means your XP back",icon:"arrow.uturn.left.circle",answers:dnb)) }

        // 4. Goals Over/Under
        let goals = answers([
            a("Fewer than 1 goal",  short:"U0.5",o?.under05,"g05"), a("At least 1 goal",   short:"O0.5",o?.over05, "g05"),
            a("Fewer than 2 goals", short:"U1.5",o?.under15,"g15"), a("2+ goals",           short:"O1.5",o?.over15, "g15"),
            a("Fewer than 3 goals", short:"U2.5",o?.under25,"g25"), a("3+ goals",           short:"O2.5",o?.over25, "g25"),
            a("Fewer than 4 goals", short:"U3.5",o?.under35,"g35"), a("4+ goals",           short:"O3.5",o?.over35, "g35"),
            a("5+ goals",           short:"O4.5",o?.over45, "g45"),
        ])
        if !goals.isEmpty { questions.append(Question(category:"🥅 HOW MANY GOALS?",prompt:"How many goals will be scored?",icon:"soccerball",answers:goals)) }

        // 5. First Half Goals
        let htg = answers([a("No first-half goals",short:"U0.5",o?.htUnder05,"ht05"),a("1+ first-half goal",short:"O0.5",o?.htOver05,"ht05"),a("2+ first-half goals",short:"O1.5",o?.htOver15,"ht15")])
        if !htg.isEmpty { questions.append(Question(category:"⏱ FIRST HALF GOALS",prompt:"Goals before half time?",icon:"1.circle",answers:htg)) }

        // 6. Both Teams Score
        let btts = answers([a("Yes — both teams score",short:"YES",o?.bttsYes,"btts"),a("No — at least one blank",short:"NO",o?.bttsNo,"btts")])
        if !btts.isEmpty { questions.append(Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both teams get on the scoresheet?",icon:"arrow.left.and.right.circle",answers:btts)) }

        // 7. Half Time Result
        let htr = answers([a("\(match.home) leading",short:"HOME",o?.htHomeWin,"ht_r"),a("Level at half time",short:"DRAW",o?.htDraw,"ht_r"),a("\(match.away) leading",short:"AWAY",o?.htAwayWin,"ht_r")])
        if !htr.isEmpty { questions.append(Question(category:"📊 HALF TIME SCORE",prompt:"Who's leading at half time?",icon:"clock",answers:htr)) }

        // 8. Win to Nil ✅ NEW
        let wtn = answers([a("\(match.home) win & keep clean sheet",short:"H-NIL",o?.homeWinToNil,"wtn_h"),a("\(match.away) win & keep clean sheet",short:"A-NIL",o?.awayWinToNil,"wtn_a")])
        if !wtn.isEmpty { questions.append(Question(category:"🔒 WIN TO NIL",prompt:"Win without conceding?",icon:"lock.shield",answers:wtn)) }

        // 9. Clean Sheet
        let cs = answers([a("\(match.home) keep a clean sheet",short:"HOME",o?.homeCleanSheet,"cs_h"),a("\(match.away) keep a clean sheet",short:"AWAY",o?.awayCleanSheet,"cs_a")])
        if !cs.isEmpty { questions.append(Question(category:"🧤 CLEAN SHEET",prompt:"Will a team shut out the opposition?",icon:"hand.raised.slash",answers:cs)) }

        // 10. Corners
        let corners = answers([
            a("Fewer than 8",short:"U7.5",o?.cornersUnder75,"c75"),a("8+",short:"O7.5",o?.cornersOver75,"c75"),
            a("Fewer than 9",short:"U8.5",o?.cornersUnder85,"c85"),a("9+",short:"O8.5",o?.cornersOver85,"c85"),
            a("Fewer than 10",short:"U9.5",o?.cornersUnder95,"c95"),a("10+",short:"O9.5",o?.cornersOver95,"c95"),
            a("11+",short:"O10.5",o?.cornersOver105,"c105"),
        ])
        if !corners.isEmpty { questions.append(Question(category:"🚩 CORNERS",prompt:"How many corners in the match?",icon:"flag",answers:corners)) }

        // 11. Cards
        let cards = answers([
            a("Fewer than 2 cards",short:"U1.5",o?.cardsUnder15,"cr15"),a("2+ cards",short:"O1.5",o?.cardsOver15,"cr15"),
            a("Fewer than 3 cards",short:"U2.5",o?.cardsUnder25,"cr25"),a("3+ cards",short:"O2.5",o?.cardsOver25,"cr25"),
            a("4+ cards",short:"O3.5",o?.cardsOver35,"cr35"),
        ])
        if !cards.isEmpty { questions.append(Question(category:"🟨 BOOKINGS",prompt:"How many yellow cards will be shown?",icon:"rectangle.portrait",answers:cards)) }

        // 12. Correct Score ✅ NEW
        if let scores = o?.correctScores, !scores.isEmpty {
            let csAnswers = scores.map { Answer($0.score, short: $0.score, odds: $0.odd, group: "cs_\($0.score)") }
            questions.append(Question(category:"🎯 CORRECT SCORE",prompt:"What will the final scoreline be?",icon:"number.circle",answers:csAnswers))
        }

        // 13. Anytime Goalscorer
        let anytime = (o?.playerAnytime ?? []).compactMap { p -> Answer? in
            guard p.odd > 1 else { return nil }
            return Answer(p.name, short: "⚽", odds: p.odd, group: "anytime_\(p.name)")
        }
        if !anytime.isEmpty { questions.append(Question(category:"⚽ ANYTIME GOALSCORER",prompt:"Who scores at any point?",icon:"person.fill.checkmark",answers:anytime)) }

        // 14. First Goalscorer
        let first = (o?.playerFirstGoal ?? []).compactMap { p -> Answer? in
            guard p.odd > 1 else { return nil }
            return Answer(p.name, short: "1ST", odds: p.odd, group: "first_\(p.name)")
        }
        if !first.isEmpty { questions.append(Question(category:"🥇 FIRST GOALSCORER",prompt:"Who scores first?",icon:"1.circle.fill",answers:first)) }

        // 15. To Be Carded
        let carded = (o?.playerToBeCarded ?? []).compactMap { p -> Answer? in
            guard p.odd > 1 else { return nil }
            return Answer(p.name, short: "🟨", odds: p.odd, group: "card_\(p.name)")
        }
        if !carded.isEmpty { questions.append(Question(category:"🟨 WHO GETS BOOKED?",prompt:"Which player picks up a card?",icon:"rectangle.portrait.fill",answers:carded)) }

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
            clearAnswers(); isSubmitting = false; return true
        } catch { errorMessage = error.localizedDescription; isSubmitting = false; return false }
    }
}
