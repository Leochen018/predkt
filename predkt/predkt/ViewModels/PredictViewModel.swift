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

    // ✅ Championship = 40, NOT 66
    private let topLeagueIDs = [39,40,45,48,140,143,135,137,78,529,61,94,88,2,3,848,4,32]

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
    func isLocked(_ answer: Answer) -> Bool  { lockedAnswers.contains(answer) }
    func conflicts(_ answer: Answer) -> Bool { lockedAnswers.contains { $0.group == answer.group && $0 != answer } }
    func clearAnswers() { lockedAnswers = [] }

    // MARK: - Fallback Questions

    private func fallbackQuestions(for match: Match) -> [Question] {[
        Question(category:"⚽ MATCH RESULT", prompt:"Who wins this match?", icon:"trophy", answers:[
            Answer("\(match.home) Win", short:"HOME", odds:2.10, group:"result"),
            Answer("Draw",              short:"DRAW", odds:3.20, group:"result"),
            Answer("\(match.away) Win", short:"AWAY", odds:1.90, group:"result"),
        ]),
        Question(category:"🛡 DOUBLE CHANCE", prompt:"Which two outcomes can you cover?", icon:"shield.lefthalf.filled", answers:[
            Answer("\(match.home) or Draw", short:"1X", odds:1.35, group:"dc"),
            Answer("Either team wins",      short:"12", odds:1.25, group:"dc"),
            Answer("\(match.away) or Draw", short:"X2", odds:1.40, group:"dc"),
        ]),
        Question(category:"🥅 HOW MANY GOALS?", prompt:"How many goals will be scored?", icon:"soccerball", answers:[
            Answer("Fewer than 3 goals", short:"U2.5", odds:2.00, group:"g25"),
            Answer("3+ goals",           short:"O2.5", odds:1.80, group:"g25"),
        ]),
        Question(category:"🔀 BOTH TEAMS SCORE?", prompt:"Will both teams get on the scoresheet?", icon:"arrow.left.and.right.circle", answers:[
            Answer("Yes — both score",        short:"YES", odds:2.30, group:"btts"),
            Answer("No — at least one blank", short:"NO",  odds:1.60, group:"btts"),
        ]),
        Question(category:"📊 HALF TIME SCORE", prompt:"Who's leading at half time?", icon:"clock", answers:[
            Answer("\(match.home) leading", short:"HOME", odds:2.60, group:"ht_r"),
            Answer("Level at half time",    short:"DRAW", odds:2.10, group:"ht_r"),
            Answer("\(match.away) leading", short:"AWAY", odds:3.50, group:"ht_r"),
        ]),
    ]}

    // MARK: - Build All Questions

    func getQuestions(for match: Match) -> [Question] {
        let o = match.odds
        var q: [Question] = []

        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func ans(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }
        func players(_ list: [PlayerOdd]?, group: String, limit: Int = 12) -> [Answer] {
            (list ?? []).prefix(limit).compactMap { p in
                guard p.odd > 1 else { return nil }
                return Answer(p.name, short: "👤", odds: p.odd, group: "\(group)_\(p.name)")
            }
        }

        // 1. Match Result
        let r = ans([a("\(match.home) Win",short:"HOME",o?.homeWin,"result"),a("Draw",short:"DRAW",o?.draw,"result"),a("\(match.away) Win",short:"AWAY",o?.awayWin,"result")])
        if !r.isEmpty { q.append(Question(category:"⚽ MATCH RESULT",prompt:"Who wins this match?",icon:"trophy",answers:r)) }

        // 2. Double Chance
        let dc = ans([a("\(match.home) or Draw",short:"1X",o?.homeOrDraw,"dc"),a("Either team wins",short:"12",o?.homeOrAway,"dc"),a("\(match.away) or Draw",short:"X2",o?.awayOrDraw,"dc")])
        if !dc.isEmpty { q.append(Question(category:"🛡 DOUBLE CHANCE",prompt:"Pick two outcomes",icon:"shield.lefthalf.filled",answers:dc)) }

        // 3. Draw No Bet
        let dnb = ans([a(match.home,short:"HOME",o?.dnbHome,"dnb"),a(match.away,short:"AWAY",o?.dnbAway,"dnb")])
        if !dnb.isEmpty { q.append(Question(category:"🔄 DRAW NO BET",prompt:"Win or get your XP back if it's a draw",icon:"arrow.uturn.left.circle",answers:dnb)) }

        // 4. Asian Handicap
        let ah = ans([
            a("\(match.home) -0.5 (must win)", short:"H-0.5", o?.ahHome05, "ah_h05"),
            a("\(match.away) -0.5 (must win)", short:"A-0.5", o?.ahAway05, "ah_a05"),
            a("\(match.home) -1.5 (win by 2+)", short:"H-1.5", o?.ahHome15, "ah_h15"),
            a("\(match.away) -1.5 (win by 2+)", short:"A-1.5", o?.ahAway15, "ah_a15"),
        ])
        if !ah.isEmpty { q.append(Question(category:"⚖️ ASIAN HANDICAP",prompt:"Pick a team with a goal handicap",icon:"scalemass",answers:ah)) }

        // 5. Goals Over/Under
        let goals = ans([
            a("Fewer than 1 goal", short:"U0.5",o?.under05,"g05"), a("1+ goals",  short:"O0.5",o?.over05, "g05"),
            a("Fewer than 2 goals",short:"U1.5",o?.under15,"g15"), a("2+ goals",  short:"O1.5",o?.over15, "g15"),
            a("Fewer than 3 goals",short:"U2.5",o?.under25,"g25"), a("3+ goals",  short:"O2.5",o?.over25, "g25"),
            a("Fewer than 4 goals",short:"U3.5",o?.under35,"g35"), a("4+ goals",  short:"O3.5",o?.over35, "g35"),
            a("5+ goals",          short:"O4.5",o?.over45, "g45"),
        ])
        if !goals.isEmpty { q.append(Question(category:"🥅 HOW MANY GOALS?",prompt:"Total goals in the match?",icon:"soccerball",answers:goals)) }

        // 6. Exact Goals
        let exact = ans([
            a("Exactly 0 goals", short:"0", o?.exactGoals0,    "exact_0"),
            a("Exactly 1 goal",  short:"1", o?.exactGoals1,    "exact_1"),
            a("Exactly 2 goals", short:"2", o?.exactGoals2,    "exact_2"),
            a("Exactly 3 goals", short:"3", o?.exactGoals3,    "exact_3"),
            a("Exactly 4 goals", short:"4", o?.exactGoals4,    "exact_4"),
            a("5 or more goals", short:"5+",o?.exactGoals5plus,"exact_5"),
        ])
        if !exact.isEmpty { q.append(Question(category:"🔢 EXACT GOALS",prompt:"What's the exact number of goals?",icon:"number.circle",answers:exact)) }

        // 7. First Half Goals
        let htg = ans([a("No HT goals",short:"U0.5",o?.htUnder05,"htg05"),a("1+ HT goals",short:"O0.5",o?.htOver05,"htg05"),a("2+ HT goals",short:"O1.5",o?.htOver15,"htg15")])
        if !htg.isEmpty { q.append(Question(category:"⏱ FIRST HALF GOALS",prompt:"Goals before the break?",icon:"1.circle",answers:htg)) }

        // 8. Both Teams Score
        let btts = ans([a("Yes — both score",short:"YES",o?.bttsYes,"btts"),a("No — one team blank",short:"NO",o?.bttsNo,"btts")])
        if !btts.isEmpty { q.append(Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both teams get on the scoresheet?",icon:"arrow.left.and.right.circle",answers:btts)) }

        // 9. BTTS by Half
        let bttsH = ans([a("Both score in first half",short:"1H-YES",o?.bttsFirstHalf,"btts_1h"),a("Both score in second half",short:"2H-YES",o?.bttsSecondHalf,"btts_2h")])
        if !bttsH.isEmpty { q.append(Question(category:"🔀 BTTS BY HALF",prompt:"In which half do both teams score?",icon:"arrow.left.and.right",answers:bttsH)) }

        // 10. Half Time Result
        let htr = ans([a("\(match.home) leading",short:"HOME",o?.htHomeWin,"ht_r"),a("Level at HT",short:"DRAW",o?.htDraw,"ht_r"),a("\(match.away) leading",short:"AWAY",o?.htAwayWin,"ht_r")])
        if !htr.isEmpty { q.append(Question(category:"📊 HALF TIME RESULT",prompt:"Who's leading at half time?",icon:"clock",answers:htr)) }

        // 11. HT/FT Double Result
        let htft = ans([
            a("Home at HT & FT",  short:"H/H", o?.htftHomeHome,  "htft_hh"),
            a("Draw at HT, Home win FT", short:"D/H", o?.htftDrawHome, "htft_dh"),
            a("Away at HT & FT",  short:"A/A", o?.htftAwayAway,  "htft_aa"),
            a("Home at HT, Draw FT", short:"H/D", o?.htftHomeDraw, "htft_hd"),
            a("Draw at HT & FT",  short:"D/D", o?.htftDrawDraw,  "htft_dd"),
            a("Away at HT, Draw FT", short:"A/D", o?.htftAwayDraw, "htft_ad"),
            a("Home at HT, Away win FT",short:"H/A",o?.htftHomeAway,"htft_ha"),
            a("Draw at HT, Away win FT",short:"D/A",o?.htftDrawAway,"htft_da"),
            a("Away at HT, Home win FT",short:"A/H",o?.htftAwayHome,"htft_ah"),
        ])
        if !htft.isEmpty { q.append(Question(category:"📈 HALF TIME / FULL TIME",prompt:"Who's winning at HT and who wins the match?",icon:"arrow.up.right.circle",answers:htft)) }

        // 12. Win to Nil
        let wtn = ans([a("\(match.home) win & clean sheet",short:"H-NIL",o?.homeWinToNil,"wtn_h"),a("\(match.away) win & clean sheet",short:"A-NIL",o?.awayWinToNil,"wtn_a")])
        if !wtn.isEmpty { q.append(Question(category:"🔒 WIN TO NIL",prompt:"Win without conceding?",icon:"lock.shield",answers:wtn)) }

        // 13. Clean Sheet
        let cs = ans([a("\(match.home) clean sheet",short:"HOME",o?.homeCleanSheet,"cs_h"),a("\(match.away) clean sheet",short:"AWAY",o?.awayCleanSheet,"cs_a")])
        if !cs.isEmpty { q.append(Question(category:"🧤 CLEAN SHEET",prompt:"Will a goalkeeper keep it shut?",icon:"hand.raised.slash",answers:cs)) }

        // 14. Correct Score
        if let scores = o?.correctScores, !scores.isEmpty {
            let csAns = scores.map { Answer($0.score, short: $0.score, odds: $0.odd, group: "cs_\($0.score)") }
            q.append(Question(category:"🎯 CORRECT SCORE",prompt:"What's the final scoreline?",icon:"number.circle",answers:csAns))
        }

        // 15. Corners
        let corners = ans([
            a("Fewer than 8 corners", short:"U7.5", o?.cornersUnder75, "c75"), a("8+ corners",  short:"O7.5", o?.cornersOver75,  "c75"),
            a("Fewer than 9 corners", short:"U8.5", o?.cornersUnder85, "c85"), a("9+ corners",  short:"O8.5", o?.cornersOver85,  "c85"),
            a("Fewer than 10 corners",short:"U9.5", o?.cornersUnder95, "c95"), a("10+ corners", short:"O9.5", o?.cornersOver95,  "c95"),
            a("11+ corners",          short:"O10.5",o?.cornersOver105, "c105"),
        ])
        if !corners.isEmpty { q.append(Question(category:"🚩 CORNERS",prompt:"How many corners will there be?",icon:"flag",answers:corners)) }

        // 16. First Half Corners
        let htc = ans([
            a("Fewer than 4 HT corners",short:"U3.5",o?.htCornersUnder35,"htc35"),a("4+ HT corners",short:"O3.5",o?.htCornersOver35,"htc35"),
            a("Fewer than 5 HT corners",short:"U4.5",o?.htCornersUnder45,"htc45"),a("5+ HT corners",short:"O4.5",o?.htCornersOver45,"htc45"),
        ])
        if !htc.isEmpty { q.append(Question(category:"🚩 FIRST HALF CORNERS",prompt:"Corners before half time?",icon:"flag.fill",answers:htc)) }

        // 17. Cards
        let cards = ans([
            a("Fewer than 2 cards",short:"U1.5",o?.cardsUnder15,"cr15"),a("2+ cards",short:"O1.5",o?.cardsOver15,"cr15"),
            a("Fewer than 3 cards",short:"U2.5",o?.cardsUnder25,"cr25"),a("3+ cards",short:"O2.5",o?.cardsOver25,"cr25"),
            a("Fewer than 4 cards",short:"U3.5",o?.cardsUnder35,"cr35"),a("4+ cards",short:"O3.5",o?.cardsOver35,"cr35"),
            a("5+ cards",          short:"O4.5",o?.cardsOver45,  "cr45"),
        ])
        if !cards.isEmpty { q.append(Question(category:"🟨 TOTAL BOOKINGS",prompt:"How many yellow cards will be shown?",icon:"rectangle.portrait",answers:cards)) }

        // 18. Total Shots
        let shots = ans([
            a("Fewer than 9 shots", short:"U8.5",  o?.shotsUnder85,  "sh85"),  a("9+ shots",  short:"O8.5",  o?.shotsOver85,  "sh85"),
            a("Fewer than 11 shots",short:"U10.5", o?.shotsUnder105, "sh105"), a("11+ shots", short:"O10.5", o?.shotsOver105, "sh105"),
        ])
        if !shots.isEmpty { q.append(Question(category:"🎯 TOTAL SHOTS",prompt:"How many shots in the match?",icon:"target",answers:shots)) }

        // 19. Offsides
        let off = ans([
            a("Fewer than 2 offsides",short:"U1.5",o?.offsidesUnder15,"off15"),a("2+ offsides",short:"O1.5",o?.offsidesOver15,"off15"),
            a("Fewer than 3 offsides",short:"U2.5",o?.offsidesUnder25,"off25"),a("3+ offsides",short:"O2.5",o?.offsidesOver25,"off25"),
        ])
        if !off.isEmpty { q.append(Question(category:"🚩 OFFSIDES",prompt:"How many offside calls?",icon:"flag.2.crossed",answers:off)) }

        // 20. Anytime Goalscorer
        let any = players(o?.playerAnytime, group:"any")
        if !any.isEmpty { q.append(Question(category:"⚽ ANYTIME GOALSCORER",prompt:"Who scores at any point?",icon:"person.fill.checkmark",answers:any)) }

        // 21. First Goalscorer
        let first = players(o?.playerFirstGoal, group:"first")
        if !first.isEmpty { q.append(Question(category:"🥇 FIRST GOALSCORER",prompt:"Who opens the scoring?",icon:"1.circle.fill",answers:first)) }

        // 22. Player to Score 2+
        let score2 = players(o?.playerToBeScored2, group:"score2")
        if !score2.isEmpty { q.append(Question(category:"⚽⚽ SCORE 2+ GOALS",prompt:"Who scores a brace or more?",icon:"2.circle.fill",answers:score2)) }

        // 23. Hat-trick
        let hat = players(o?.playerHatTrick, group:"hattrick")
        if !hat.isEmpty { q.append(Question(category:"🎩 HAT-TRICK",prompt:"Who bags a hat-trick?",icon:"3.circle.fill",answers:hat)) }

        // 24. Player to Assist
        let assist = players(o?.playerToAssist, group:"assist")
        if !assist.isEmpty { q.append(Question(category:"🅰️ PLAYER TO ASSIST",prompt:"Who sets up a goal?",icon:"hand.point.right.fill",answers:assist)) }

        // 25. Player to Be Carded
        let carded = players(o?.playerToBeCarded, group:"card")
        if !carded.isEmpty { q.append(Question(category:"🟨 PLAYER BOOKED",prompt:"Who picks up a yellow card?",icon:"rectangle.portrait.fill",answers:carded)) }

        // 26. Player to Be Fouled
        let fouled = players(o?.playerToBeFouled, group:"fouled")
        if !fouled.isEmpty { q.append(Question(category:"🤕 PLAYER TO BE FOULED",prompt:"Who wins the most free kicks?",icon:"figure.fall",answers:fouled)) }

        // 27. Player Shots on Target
        let soTarget = players(o?.playerShotsOnTarget, group:"sot")
        if !soTarget.isEmpty { q.append(Question(category:"🎯 SHOTS ON TARGET",prompt:"Who tests the keeper most?",icon:"scope",answers:soTarget)) }

        return q.isEmpty ? fallbackQuestions(for: match) : q
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
