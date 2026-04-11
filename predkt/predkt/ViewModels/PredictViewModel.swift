import Foundation
import Combine
import Supabase

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSubmitting = false
    @Published var lockedAnswers: [Answer] = []
    @Published var deleteMessage: String?

    private var matchesLoaded = false
    private let supabaseManager = SupabaseManager.shared

    // MARK: - League priority order
    // ✅ Fixed, deterministic — Championship (40) is slot 2
    static let leaguePriority: [String] = [
        "Premier League",       // 39
        "Championship",         // 40 ✅
        "Champions League",     // 2
        "Europa League",        // 3
        "Conference League",    // 848
        "FA Cup",               // 45
        "EFL Cup",              // 48
        "La Liga",              // 140
        "La Liga 2",            // 143
        "Serie A",              // 135
        "Serie B",              // 137
        "Bundesliga",           // 78
        "Bundesliga 2",         // 529
        "Ligue 1",              // 61
        "Ligue 2",              // 94 (not 66)
        "Primeira Liga",        // 94
        "Eredivisie",           // 88
        "World Cup",            // 1
        "Euro Championship",    // 4
        "Nations League",       // 5
        "Copa del Rey",
        "Coppa Italia",
        "DFB Pokal",
        "Coupe de France",
    ]

    // MARK: - Answer
    // ✅ communityPercent is deterministic — derived from probability, not random

    struct Answer: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let shortLabel: String
        let probability: Int
        let odds: Double
        let group: String

        var xpValue: Int { max(1, 10 + (100 - probability)) }
        var probabilityDisplay: String { "\(probability)%" }

        // ✅ Deterministic — no Int.random. Shows community agreement ≈ implied probability
        var communityPercent: Int { min(92, max(8, probability)) }

        static func == (lhs: Answer, rhs: Answer) -> Bool { lhs.id == rhs.id }

        init(_ label: String, short: String, odds: Double, group: String) {
            self.label = label; self.shortLabel = short; self.odds = odds; self.group = group
            self.probability = min(99, max(1, Int(round(1.0 / odds * 100))))
        }
    }

    // MARK: - Question

    struct Question: Identifiable {
        let id = UUID()
        let category: String; let prompt: String; let icon: String
        let answers: [Answer]
        var isEmpty: Bool { answers.isEmpty }
    }

    var totalXP: Int  { lockedAnswers.reduce(0) { $0 + $1.xpValue } }
    var isCombo: Bool { lockedAnswers.count > 1 }

    func lockAnswer(_ answer: Answer) {
        if let idx = lockedAnswers.firstIndex(of: answer) { lockedAnswers.remove(at: idx) }
        else { lockedAnswers.removeAll { $0.group == answer.group }; lockedAnswers.append(answer) }
    }
    func isLocked(_ a: Answer) -> Bool  { lockedAnswers.contains(a) }
    func conflicts(_ a: Answer) -> Bool { lockedAnswers.contains { $0.group == a.group && $0 != a } }
    func clearAnswers() { lockedAnswers = [] }

    func goToNextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }
    func goToPreviousDay() {
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        if Calendar.current.startOfDay(for: prev) >= Calendar.current.startOfDay(for: Date()) {
            selectedDate = prev
        }
    }

    // MARK: - Filtering and Grouping
    // ✅ Fully deterministic — sorted by date then kickoff time, no randomness

    private func parseDate(_ raw: String) -> Date {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw) ?? Date()
    }

    var filteredMatches: [Match] {
        let cal = Calendar.current
        return matches
            .filter { cal.isDate(parseDate($0.rawDate), inSameDayAs: selectedDate) }
            .sorted {
                // ✅ Deterministic sort: live first, then by kickoff time, then home team name
                if $0.isLive != $1.isLive { return $0.isLive }
                if $0.rawDate != $1.rawDate { return $0.rawDate < $1.rawDate }
                return $0.home < $1.home
            }
    }

    var matchesByLeague: [(league: String, matches: [Match])] {
        let priority = Self.leaguePriority

        // Group by competition
        var order: [String] = []
        var groups: [String: [Match]] = [:]
        for match in filteredMatches {
            if groups[match.competition] == nil { order.append(match.competition) }
            groups[match.competition, default: []].append(match)
        }

        // ✅ Sort leagues by priority list, then alphabetically for unlisted ones
        order.sort { a, b in
            let ai = priority.firstIndex(of: a)
            let bi = priority.firstIndex(of: b)
            switch (ai, bi) {
            case let (.some(x), .some(y)): return x < y
            case (.some, .none):           return true
            case (.none, .some):           return false
            case (.none, .none):           return a < b
            }
        }

        // Within each league sort matches by kickoff time then home name
        return order.map { league in
            let sorted = groups[league]!.sorted {
                $0.rawDate == $1.rawDate ? $0.home < $1.home : $0.rawDate < $1.rawDate
            }
            return (league: league, matches: sorted)
        }
    }

    // MARK: - Load

    func loadMatches() async {
        guard !matchesLoaded else { return }
        isLoading = true; errorMessage = nil
        do {
            matches = try await APIManager.fetchAllMatches()
            matchesLoaded = true
            print("✅ Loaded \(matches.count) matches")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ \(error)")
        }
        isLoading = false
    }

    func refreshMatches() async {
        matchesLoaded = false
        matches = []
        isLoading = true
        await loadMatches()
    }

    // MARK: - All Questions

    func getQuestions(for match: Match) -> [Question] {
        let o = match.odds
        var q: [Question] = []

        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func ans(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }
        func players(_ list: [PlayerOdd]?, grp: String, limit: Int = 12) -> [Answer] {
            (list ?? []).prefix(limit).compactMap { p in
                guard p.odd > 1 else { return nil }
                return Answer(p.name, short: "👤", odds: p.odd, group: "\(grp)_\(p.name)")
            }
        }

        // ID 1 — Match Winner
        let r = ans([a("\(match.home) Win",short:"HOME",o?.homeWin,"result"),
                     a("Draw",             short:"DRAW",o?.draw,   "result"),
                     a("\(match.away) Win",short:"AWAY",o?.awayWin,"result")])
        if !r.isEmpty { q.append(Question(category:"⚽ MATCH RESULT",prompt:"Who wins this match?",icon:"trophy",answers:r)) }

        // ID 2 — Home/Away
        let ha = ans([a("\(match.home) to win",short:"HOME",o?.homeWinNoDraw,"ha"),
                      a("\(match.away) to win",short:"AWAY",o?.awayWinNoDraw,"ha")])
        if !ha.isEmpty { q.append(Question(category:"🏆 HOME OR AWAY",prompt:"Who wins? (no draw option)",icon:"arrow.left.arrow.right",answers:ha)) }

        // ID 12 — Double Chance
        let dc = ans([a("\(match.home) or Draw",short:"1X",o?.homeOrDraw,"dc"),
                      a("Either team wins",     short:"12",o?.homeOrAway,"dc"),
                      a("\(match.away) or Draw",short:"X2",o?.awayOrDraw,"dc")])
        if !dc.isEmpty { q.append(Question(category:"🛡 DOUBLE CHANCE",prompt:"Pick two outcomes",icon:"shield.lefthalf.filled",answers:dc)) }

        // ID 13 — Draw No Bet
        let dnb = ans([a(match.home,short:"HOME",o?.dnbHome,"dnb"),
                       a(match.away,short:"AWAY",o?.dnbAway,"dnb")])
        if !dnb.isEmpty { q.append(Question(category:"🔄 DRAW NO BET",prompt:"Win or XP back on a draw",icon:"arrow.uturn.left.circle",answers:dnb)) }

        // ID 17 — Asian Handicap
        let ah = ans([a("\(match.home) -0.5",short:"H-0.5",o?.ahHome05,"ah_h05"),
                      a("\(match.away) -0.5",short:"A-0.5",o?.ahAway05,"ah_a05"),
                      a("\(match.home) -1.5",short:"H-1.5",o?.ahHome15,"ah_h15"),
                      a("\(match.away) -1.5",short:"A-1.5",o?.ahAway15,"ah_a15")])
        if !ah.isEmpty { q.append(Question(category:"⚖️ ASIAN HANDICAP",prompt:"Pick a team with a goal handicap",icon:"scalemass",answers:ah)) }

        // ID 4 — Goals Over/Under
        let goals = ans([a("At least 1 goal",  short:"O0.5",o?.over05, "g05"),
                         a("0 goals",           short:"U0.5",o?.under05,"g05"),
                         a("2+ goals",          short:"O1.5",o?.over15, "g15"),
                         a("0 or 1 goal",       short:"U1.5",o?.under15,"g15"),
                         a("3+ goals",          short:"O2.5",o?.over25, "g25"),
                         a("Under 3 goals",     short:"U2.5",o?.under25,"g25"),
                         a("4+ goals",          short:"O3.5",o?.over35, "g35"),
                         a("Under 4 goals",     short:"U3.5",o?.under35,"g35"),
                         a("5+ goals",          short:"O4.5",o?.over45, "g45"),
                         a("Under 5 goals",     short:"U4.5",o?.under45,"g45")])
        if !goals.isEmpty { q.append(Question(category:"🥅 TOTAL GOALS",prompt:"How many goals in the match?",icon:"soccerball",answers:goals)) }

        // ID 20 — Exact Goals
        let exact = ans([a("No goals",   short:"0", o?.exactGoals0,   "ex0"),
                         a("Exactly 1", short:"1",  o?.exactGoals1,   "ex1"),
                         a("Exactly 2", short:"2",  o?.exactGoals2,   "ex2"),
                         a("Exactly 3", short:"3",  o?.exactGoals3,   "ex3"),
                         a("Exactly 4", short:"4",  o?.exactGoals4,   "ex4"),
                         a("5 or more", short:"5+", o?.exactGoals5plus,"ex5")])
        if !exact.isEmpty { q.append(Question(category:"🔢 EXACT GOALS",prompt:"What's the exact goal count?",icon:"number.circle",answers:exact)) }

        // ID 5 — Goals Odd/Even
        let oe = ans([a("Odd number of goals",  short:"ODD", o?.goalsOdd, "goals_oe"),
                      a("Even number of goals", short:"EVEN",o?.goalsEven,"goals_oe")])
        if !oe.isEmpty { q.append(Question(category:"🎲 GOALS ODD/EVEN",prompt:"Will total goals be odd or even?",icon:"dice",answers:oe)) }

        // ID 6 — Home Team Goals
        let hg = ans([a("\(match.home) score 1+",short:"1+",  o?.homeOver05, "hg05"),
                      a("\(match.home) score 0", short:"0",   o?.homeUnder05,"hg05"),
                      a("\(match.home) score 2+",short:"2+",  o?.homeOver15, "hg15"),
                      a("\(match.home) score 3+",short:"3+",  o?.homeOver25, "hg25")])
        if !hg.isEmpty { q.append(Question(category:"🏠 \(match.home.uppercased()) GOALS",prompt:"How many does \(match.home) score?",icon:"house.fill",answers:hg)) }

        // ID 7 — Away Team Goals
        let ag2 = ans([a("\(match.away) score 1+",short:"1+",  o?.awayOver05, "ag05"),
                       a("\(match.away) score 0", short:"0",   o?.awayUnder05,"ag05"),
                       a("\(match.away) score 2+",short:"2+",  o?.awayOver15, "ag15"),
                       a("\(match.away) score 3+",short:"3+",  o?.awayOver25, "ag25")])
        if !ag2.isEmpty { q.append(Question(category:"✈️ \(match.away.uppercased()) GOALS",prompt:"How many does \(match.away) score?",icon:"airplane",answers:ag2)) }

        // ID 3 — Both Teams Score
        let btts = ans([a("Yes — both score",   short:"YES",o?.bttsYes,"btts"),
                        a("No — one team blank",short:"NO", o?.bttsNo, "btts")])
        if !btts.isEmpty { q.append(Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both teams score?",icon:"arrow.left.and.right.circle",answers:btts)) }

        // ID 19 — BTTS & Winner
        let bttsW = ans([a("Both score & \(match.home) win",short:"BTTS+H",o?.bttsAndHomeWin,"bttsw"),
                         a("Both score & draw",             short:"BTTS+D",o?.bttsAndDraw,   "bttsw"),
                         a("Both score & \(match.away) win",short:"BTTS+A",o?.bttsAndAwayWin,"bttsw")])
        if !bttsW.isEmpty { q.append(Question(category:"🔀 BTTS & WINNER",prompt:"Both teams score — but who wins?",icon:"plus.circle",answers:bttsW)) }

        // ID 8 — BTTS First Half
        let bttsH = ans([a("Both score in 1st half",short:"1H",o?.bttsFirstHalf,"btts1h")])
        if !bttsH.isEmpty { q.append(Question(category:"🔀 BTTS FIRST HALF",prompt:"Both teams score before HT?",icon:"1.circle",answers:bttsH)) }

        // ID 9 — BTTS Second Half
        let bttsS = ans([a("Both score in 2nd half",short:"2H",o?.bttsSecondHalf,"btts2h")])
        if !bttsS.isEmpty { q.append(Question(category:"🔀 BTTS SECOND HALF",prompt:"Both teams score after HT?",icon:"2.circle",answers:bttsS)) }

        // ID 24 — BTTS Both Halves
        let bttsBH = ans([a("Both teams score in both halves",short:"BOTH",o?.bttsBothHalves,"btts_bh")])
        if !bttsBH.isEmpty { q.append(Question(category:"🔀 BTTS BOTH HALVES",prompt:"Both teams score in both halves?",icon:"arrow.left.and.right",answers:bttsBH)) }

        // ID 10 — Half Time Result
        let ht = ans([a("\(match.home) leading",short:"HOME",o?.htHomeWin,"ht_r"),
                      a("Level at HT",          short:"DRAW",o?.htDraw,   "ht_r"),
                      a("\(match.away) leading",short:"AWAY",o?.htAwayWin,"ht_r")])
        if !ht.isEmpty { q.append(Question(category:"📊 HALF TIME RESULT",prompt:"Who's leading at half time?",icon:"clock",answers:ht)) }

        // ID 11 — Second Half Winner
        let sh = ans([a("\(match.home) win 2nd half",short:"HOME",o?.shHomeWin,"sh_r"),
                      a("Draw in 2nd half",          short:"DRAW",o?.shDraw,   "sh_r"),
                      a("\(match.away) win 2nd half",short:"AWAY",o?.shAwayWin,"sh_r")])
        if !sh.isEmpty { q.append(Question(category:"📊 SECOND HALF RESULT",prompt:"Who wins the second half?",icon:"clock.arrow.2.circlepath",answers:sh)) }

        // HT Goals
        let htg = ans([a("No 1st half goals",short:"U0.5",o?.htUnder05,"htg05"),
                       a("1+ 1st half goals",short:"O0.5",o?.htOver05, "htg05"),
                       a("2+ 1st half goals",short:"O1.5",o?.htOver15, "htg15")])
        if !htg.isEmpty { q.append(Question(category:"⏱ FIRST HALF GOALS",prompt:"Goals before the break?",icon:"1.circle.fill",answers:htg)) }

        // ID 22 — HT/FT
        let htft = ans([a("Home at HT & FT",     short:"H/H",o?.htftHomeHome,"htft_hh"),
                        a("Draw→Home",            short:"D/H",o?.htftDrawHome,"htft_dh"),
                        a("Away→Home",            short:"A/H",o?.htftAwayHome,"htft_ah"),
                        a("Home→Draw",            short:"H/D",o?.htftHomeDraw,"htft_hd"),
                        a("Draw at HT & FT",      short:"D/D",o?.htftDrawDraw,"htft_dd"),
                        a("Away→Draw",            short:"A/D",o?.htftAwayDraw,"htft_ad"),
                        a("Home→Away",            short:"H/A",o?.htftHomeAway,"htft_ha"),
                        a("Draw→Away",            short:"D/A",o?.htftDrawAway,"htft_da"),
                        a("Away at HT & FT",      short:"A/A",o?.htftAwayAway,"htft_aa")])
        if !htft.isEmpty { q.append(Question(category:"📈 HT / FULL TIME",prompt:"Result at HT and FT?",icon:"arrow.up.right.circle",answers:htft)) }

        // ID 14 — First Team to Score
        let fts = ans([a("\(match.home) score first",short:"HOME",o?.firstTeamHome,"fts"),
                       a("\(match.away) score first",short:"AWAY",o?.firstTeamAway,"fts"),
                       a("No goals",                 short:"NONE",o?.firstTeamNone,"fts")])
        if !fts.isEmpty { q.append(Question(category:"🥇 FIRST TEAM TO SCORE",prompt:"Who opens the scoring?",icon:"flag.checkered",answers:fts)) }

        // ID 15 — Last Team to Score
        let lts = ans([a("\(match.home) score last",short:"HOME",o?.lastTeamHome,"lts"),
                       a("\(match.away) score last",short:"AWAY",o?.lastTeamAway,"lts")])
        if !lts.isEmpty { q.append(Question(category:"🏁 LAST TEAM TO SCORE",prompt:"Who scores the last goal?",icon:"flag.fill",answers:lts)) }

        // ID 18 — Win to Nil
        let wtn = ans([a("\(match.home) win & clean sheet",short:"H-NIL",o?.homeWinToNil,"wtn_h"),
                       a("\(match.away) win & clean sheet",short:"A-NIL",o?.awayWinToNil,"wtn_a")])
        if !wtn.isEmpty { q.append(Question(category:"🔒 WIN TO NIL",prompt:"Win without conceding?",icon:"lock.shield",answers:wtn)) }

        // ID 21 — Clean Sheet
        let cs = ans([a("\(match.home) clean sheet",short:"HOME",o?.homeCleanSheet,"cs_h"),
                      a("\(match.away) clean sheet",short:"AWAY",o?.awayCleanSheet,"cs_a")])
        if !cs.isEmpty { q.append(Question(category:"🧤 CLEAN SHEET",prompt:"Who keeps a shutout?",icon:"hand.raised.slash",answers:cs)) }

        // ID 33 — Score in Both Halves
        let sbh = ans([a("\(match.home) score in both halves",short:"H-BH",o?.homeScoreBothHalves,"sbh_h"),
                       a("\(match.away) score in both halves",short:"A-BH",o?.awayScoreBothHalves,"sbh_a")])
        if !sbh.isEmpty { q.append(Question(category:"🔁 SCORE BOTH HALVES",prompt:"A team scores in both halves?",icon:"arrow.triangle.2.circlepath",answers:sbh)) }

        // ID 16 — Correct Score FT
        if let scores = o?.correctScores, !scores.isEmpty {
            let csAns = scores.map { Answer($0.score, short: $0.score, odds: $0.odd, group: "cs_\($0.score)") }
            q.append(Question(category:"🎯 CORRECT SCORE",prompt:"What's the exact final score?",icon:"number.circle",answers:csAns))
        }

        // ID 45 — Correct Score HT
        if let scores = o?.correctScoresHT, !scores.isEmpty {
            let csAns = scores.map { Answer("HT: \($0.score)", short: $0.score, odds: $0.odd, group: "cs_ht_\($0.score)") }
            q.append(Question(category:"🎯 CORRECT SCORE — HT",prompt:"Score at half time?",icon:"number.square",answers:csAns))
        }

        // ID 62 — Correct Score 2nd Half
        if let scores = o?.correctScoresSH, !scores.isEmpty {
            let csAns = scores.map { Answer("2H: \($0.score)", short: $0.score, odds: $0.odd, group: "cs_sh_\($0.score)") }
            q.append(Question(category:"🎯 CORRECT SCORE — 2ND HALF",prompt:"Goals in the 2nd half?",icon:"number.square.fill",answers:csAns))
        }

        // ID 37 — Winning Margin
        let wm = ans([a("\(match.home) win by 1",  short:"H+1",o?.winMarginHome1,"wm"),
                      a("\(match.home) win by 2",  short:"H+2",o?.winMarginHome2,"wm"),
                      a("\(match.home) win by 3+", short:"H+3",o?.winMarginHome3,"wm"),
                      a("\(match.away) win by 1",  short:"A+1",o?.winMarginAway1,"wm"),
                      a("\(match.away) win by 2",  short:"A+2",o?.winMarginAway2,"wm"),
                      a("\(match.away) win by 3+", short:"A+3",o?.winMarginAway3,"wm"),
                      a("Draw",                    short:"0",  o?.winMarginDraw, "wm")])
        if !wm.isEmpty { q.append(Question(category:"📏 WINNING MARGIN",prompt:"By how many goals?",icon:"ruler",answers:wm)) }

        // ID 23 — Corners
        let corners = ans([a("Under 8",   short:"U7.5", o?.cornersUnder75, "c75"),
                           a("8+ corners",short:"O7.5", o?.cornersOver75,  "c75"),
                           a("Under 9",   short:"U8.5", o?.cornersUnder85, "c85"),
                           a("9+ corners",short:"O8.5", o?.cornersOver85,  "c85"),
                           a("Under 10",  short:"U9.5", o?.cornersUnder95, "c95"),
                           a("10+",       short:"O9.5", o?.cornersOver95,  "c95"),
                           a("11+",       short:"O10.5",o?.cornersOver105, "c105")])
        if !corners.isEmpty { q.append(Question(category:"🚩 TOTAL CORNERS",prompt:"How many corners?",icon:"flag",answers:corners)) }

        // HT Corners
        let htc = ans([a("Under 4 HT corners",short:"U3.5",o?.htCornersUnder35,"htc35"),
                       a("4+ HT corners",     short:"O3.5",o?.htCornersOver35, "htc35"),
                       a("5+ HT corners",     short:"O4.5",o?.htCornersOver45, "htc45")])
        if !htc.isEmpty { q.append(Question(category:"🚩 FIRST HALF CORNERS",prompt:"Corners before HT?",icon:"flag.fill",answers:htc)) }

        // Cards
        let cards = ans([a("Under 2 cards",short:"U1.5",o?.cardsUnder15,"cr15"),
                         a("2+ cards",     short:"O1.5",o?.cardsOver15, "cr15"),
                         a("Under 3",      short:"U2.5",o?.cardsUnder25,"cr25"),
                         a("3+ cards",     short:"O2.5",o?.cardsOver25, "cr25"),
                         a("Under 4",      short:"U3.5",o?.cardsUnder35,"cr35"),
                         a("4+ cards",     short:"O3.5",o?.cardsOver35, "cr35"),
                         a("5+ cards",     short:"O4.5",o?.cardsOver45, "cr45")])
        if !cards.isEmpty { q.append(Question(category:"🟨 TOTAL BOOKINGS",prompt:"How many yellow cards?",icon:"rectangle.portrait",answers:cards)) }

        // ID 25 — Total Shots
        let shots = ans([a("Under 9 shots", short:"U8.5", o?.shotsUnder85,  "sh85"),
                         a("9+ shots",      short:"O8.5", o?.shotsOver85,   "sh85"),
                         a("Under 11",      short:"U10.5",o?.shotsUnder105, "sh105"),
                         a("11+ shots",     short:"O10.5",o?.shotsOver105,  "sh105"),
                         a("13+ shots",     short:"O12.5",o?.shotsOver125,  "sh125")])
        if !shots.isEmpty { q.append(Question(category:"🎯 TOTAL SHOTS",prompt:"How many shots?",icon:"scope",answers:shots)) }

        // ID 5 — Team Goals Odd/Even
        let teamOE = ans([a("\(match.home) scores odd",  short:"H-ODD", o?.homeGoalsOdd, "h_oe"),
                          a("\(match.home) scores even", short:"H-EVEN",o?.homeGoalsEven,"h_oe"),
                          a("\(match.away) scores odd",  short:"A-ODD", o?.awayGoalsOdd, "a_oe"),
                          a("\(match.away) scores even", short:"A-EVEN",o?.awayGoalsEven,"a_oe")])
        if !teamOE.isEmpty { q.append(Question(category:"🎲 TEAM GOALS ODD/EVEN",prompt:"Team goal tally odd or even?",icon:"dice.fill",answers:teamOE)) }

        // ID 28 — Anytime Goalscorer
        let any = players(o?.playerAnytime, grp:"any")
        if !any.isEmpty { q.append(Question(category:"⚽ ANYTIME GOALSCORER",prompt:"Who scores at any point?",icon:"person.fill.checkmark",answers:any)) }

        // ID 26 — First Goalscorer
        let first = players(o?.playerFirstGoal, grp:"first")
        if !first.isEmpty { q.append(Question(category:"🥇 FIRST GOALSCORER",prompt:"Who opens the scoring?",icon:"1.circle.fill",answers:first)) }

        // ID 27 — Last Goalscorer
        let last = players(o?.playerLastGoal, grp:"last")
        if !last.isEmpty { q.append(Question(category:"🏁 LAST GOALSCORER",prompt:"Who scores the final goal?",icon:"flag.checkered",answers:last)) }

        // 2+ Goals / Hat-trick
        let score2 = players(o?.playerToBeScored2, grp:"score2")
        if !score2.isEmpty { q.append(Question(category:"⚽⚽ SCORE 2+ GOALS",prompt:"Who scores a brace or more?",icon:"2.circle.fill",answers:score2)) }

        let hat = players(o?.playerHatTrick, grp:"hattrick")
        if !hat.isEmpty { q.append(Question(category:"🎩 HAT-TRICK",prompt:"Who bags a hat-trick?",icon:"3.circle.fill",answers:hat)) }

        // ID 30 — Assist
        let assist = players(o?.playerToAssist, grp:"assist")
        if !assist.isEmpty { q.append(Question(category:"🅰️ PLAYER TO ASSIST",prompt:"Who sets up a goal?",icon:"hand.point.right.fill",answers:assist)) }

        // ID 29 — Player Booked
        let carded = players(o?.playerToBeCarded, grp:"card")
        if !carded.isEmpty { q.append(Question(category:"🟨 PLAYER BOOKED",prompt:"Who picks up a yellow card?",icon:"rectangle.portrait.fill",answers:carded)) }

        // ID 32 — Player Fouled
        let fouled = players(o?.playerToBeFouled, grp:"fouled")
        if !fouled.isEmpty { q.append(Question(category:"🤕 MOST FOULED PLAYER",prompt:"Who wins the most free kicks?",icon:"figure.fall",answers:fouled)) }

        // ID 31 — Shots on Target
        let sot = players(o?.playerShotsOnTarget, grp:"sot")
        if !sot.isEmpty { q.append(Question(category:"🎯 SHOTS ON TARGET",prompt:"Who tests the keeper most?",icon:"scope",answers:sot)) }

        return q.isEmpty ? fallbackQuestions(for: match) : q
    }

    private func fallbackQuestions(for match: Match) -> [Question] {[
        Question(category:"⚽ MATCH RESULT",prompt:"Who wins?",icon:"trophy",answers:[
            Answer("\(match.home) Win",short:"HOME",odds:2.10,group:"result"),
            Answer("Draw",             short:"DRAW",odds:3.20,group:"result"),
            Answer("\(match.away) Win",short:"AWAY",odds:1.90,group:"result"),
        ]),
        Question(category:"🥅 TOTAL GOALS",prompt:"How many goals?",icon:"soccerball",answers:[
            Answer("Under 3 goals",short:"U2.5",odds:2.00,group:"g25"),
            Answer("3+ goals",     short:"O2.5",odds:1.80,group:"g25"),
        ]),
        Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both teams score?",icon:"arrow.left.and.right.circle",answers:[
            Answer("Yes — both score",  short:"YES",odds:2.30,group:"btts"),
            Answer("No — one team blank",short:"NO",odds:1.60,group:"btts"),
        ]),
        Question(category:"📊 HALF TIME RESULT",prompt:"Score at half time?",icon:"clock",answers:[
            Answer("\(match.home) leading",short:"HOME",odds:2.60,group:"ht_r"),
            Answer("Level at HT",          short:"DRAW",odds:2.10,group:"ht_r"),
            Answer("\(match.away) leading",short:"AWAY",odds:3.50,group:"ht_r"),
        ]),
    ]}

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
            NotificationManager.shared.scheduleKickoffReminder(for: match)
            clearAnswers(); isSubmitting = false; return true
        } catch {
            errorMessage = error.localizedDescription; isSubmitting = false; return false
        }
    }
}
