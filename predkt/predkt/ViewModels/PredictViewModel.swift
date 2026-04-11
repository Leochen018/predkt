import Foundation
import Combine
import Supabase

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match]  = []
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var isLoading         = false
    @Published var isLoadingOdds     = false   // shown when tapping a match
    @Published var errorMessage: String?
    @Published var isSubmitting      = false
    @Published var lockedAnswers: [Answer] = []

    // Odds loaded lazily per match
    @Published var currentMatchOdds: MatchOdds? = nil

    // User favourites
    @Published var favouriteLeagueIds:  Set<Int>    = []
    @Published var favouriteTeamNames:  Set<String> = []

    private var matchesLoaded = false
    private var cancellables  = Set<AnyCancellable>()
    private let supabaseManager = SupabaseManager.shared

    static let leaguePriority: [String] = [
        "Premier League","Championship","Champions League","Europa League",
        "Conference League","FA Cup","EFL Cup","La Liga","La Liga 2",
        "Serie A","Serie B","Bundesliga","Bundesliga 2","Ligue 1",
        "Ligue 2","Primeira Liga","Eredivisie",
    ]

    init() {
        // ✅ Listen for background match refresh (from APIManager stale-while-revalidate)
        NotificationCenter.default.publisher(for: .matchesRefreshed)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let fresh = notification.object as? [Match] {
                    self?.matches = fresh
                    print("🔄 Matches refreshed in background: \(fresh.count)")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Answer

    struct Answer: Identifiable, Equatable {
        let id = UUID()
        let label: String; let shortLabel: String
        let probability: Int; let odds: Double; let group: String
        var xpValue: Int          { max(1, 10 + (100 - probability)) }
        var probabilityDisplay: String { "\(probability)%" }
        var communityPercent: Int { min(92, max(8, probability)) }
        static func == (lhs: Answer, rhs: Answer) -> Bool { lhs.id == rhs.id }
        init(_ label: String, short: String, odds: Double, group: String) {
            self.label=label; self.shortLabel=short; self.odds=odds; self.group=group
            self.probability=min(99,max(1,Int(round(1.0/odds*100))))
        }
    }

    struct Question: Identifiable {
        let id = UUID()
        let category: String; let prompt: String; let icon: String
        let answers: [Answer]
    }

    var totalXP: Int  { lockedAnswers.reduce(0) { $0 + $1.xpValue } }
    var isCombo: Bool { lockedAnswers.count > 1 }

    func lockAnswer(_ answer: Answer) {
        if let idx = lockedAnswers.firstIndex(of: answer) { lockedAnswers.remove(at: idx) }
        else { lockedAnswers.removeAll { $0.group == answer.group }; lockedAnswers.append(answer) }
    }
    func isLocked(_ a: Answer) -> Bool  { lockedAnswers.contains(a) }
    func conflicts(_ a: Answer) -> Bool { lockedAnswers.contains { $0.group == a.group && $0 != a } }
    func clearAnswers() { lockedAnswers = []; currentMatchOdds = nil }

    // MARK: - Navigation

    func goToNextDay() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        selectedDate = next
        // ✅ Prefetch odds for next day's matches
        APIManager.prefetchOdds(for: matchesForDate(next))
    }

    func goToPreviousDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let prev  = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        if prev >= today {
            selectedDate = prev
            APIManager.prefetchOdds(for: matchesForDate(prev))
        }
    }

    // MARK: - Date Filtering (local timezone)

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = .current
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func localDateString(from rawDate: String) -> String {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: rawDate) { return Self.localDateFormatter.string(from: d) }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: rawDate) { return Self.localDateFormatter.string(from: d) }
        return String(rawDate.prefix(10))
    }

    private var selectedDateString: String {
        Self.localDateFormatter.string(from: selectedDate)
    }

    private func matchesForDate(_ date: Date) -> [Match] {
        let target = Self.localDateFormatter.string(from: date)
        return matches.filter { localDateString(from: $0.rawDate) == target }
    }

    var filteredMatches: [Match] {
        matchesForDate(selectedDate).sorted {
            if $0.isLive != $1.isLive { return $0.isLive }
            if $0.rawDate != $1.rawDate { return $0.rawDate < $1.rawDate }
            return $0.home < $1.home
        }
    }

    var matchesByLeague: [(league: String, matches: [Match], isFavourite: Bool)] {
        let priority = Self.leaguePriority
        var order:    [String]           = []
        var groups:   [String: [Match]]  = [:]
        var leagueFav:[String: Bool]     = [:]

        for match in filteredMatches {
            if groups[match.competition] == nil { order.append(match.competition) }
            groups[match.competition, default: []].append(match)
            if !(leagueFav[match.competition] ?? false) {
                leagueFav[match.competition] = isFavouriteMatch(match)
            }
        }

        order.sort { a, b in
            let af = leagueFav[a] ?? false; let bf = leagueFav[b] ?? false
            if af != bf { return af }
            let ai = priority.firstIndex(of: a); let bi = priority.firstIndex(of: b)
            switch (ai, bi) {
            case let (.some(x), .some(y)): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a < b
            }
        }

        return order.map { league in
            var sorted = groups[league]!.sorted {
                let af = isFavouriteMatch($0), bf = isFavouriteMatch($1)
                if af != bf { return af }
                if $0.isLive != $1.isLive { return $0.isLive }
                return $0.rawDate < $1.rawDate
            }
            return (league: league, matches: sorted, isFavourite: leagueFav[league] ?? false)
        }
    }

    func isFavouriteMatch(_ match: Match) -> Bool {
        favouriteLeagueIds.contains(match.leagueId)
        || favouriteTeamNames.contains(match.home)
        || favouriteTeamNames.contains(match.away)
    }

    var datesWithMatches: Set<String> {
        Set(matches.map { localDateString(from: $0.rawDate) })
    }

    func hasMatches(on date: Date) -> Bool {
        datesWithMatches.contains(Self.localDateFormatter.string(from: date))
    }

    // MARK: - Load

    func loadMatches() async {
        guard !matchesLoaded else { return }
        isLoading = true; errorMessage = nil
        do {
            async let matchFetch   = APIManager.fetchAllMatches()
            async let profileFetch = supabaseManager.fetchUserProfile()
            let (fetchedMatches, profile) = try await (matchFetch, profileFetch)

            matches       = fetchedMatches
            matchesLoaded = true

            if let s = profile?.favourite_league, !s.isEmpty {
                favouriteLeagueIds = Set(s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
            }
            if let s = profile?.favourite_team, !s.isEmpty {
                favouriteTeamNames = Set(s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }

            print("✅ \(matches.count) matches, \(datesWithMatches.count) days")

            // Auto-advance to first day with matches if today is empty
            if filteredMatches.isEmpty {
                let cal = Calendar.current
                for i in 0..<30 {
                    guard let candidate = cal.date(byAdding: .day, value: i, to: selectedDate),
                          hasMatches(on: candidate) else { continue }
                    selectedDate = candidate
                    break
                }
            }

            // ✅ Pre-fetch odds for today's matches in background
            APIManager.prefetchOdds(for: filteredMatches)

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Load error: \(error)")
        }
        isLoading = false
    }

    func refreshMatches() async {
        matchesLoaded = false; matches = []; isLoading = true
        do {
            matches       = try await APIManager.forceRefresh()
            matchesLoaded = true
            if filteredMatches.isEmpty {
                let cal = Calendar.current
                for i in 0..<30 {
                    guard let candidate = cal.date(byAdding: .day, value: i, to: selectedDate),
                          hasMatches(on: candidate) else { continue }
                    selectedDate = candidate; break
                }
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    // ✅ Lazy odds loading — called when user taps a match
    func loadOdds(for match: Match) async {
        currentMatchOdds = nil
        guard !match.isLive, !match.isFinished else { return }
        isLoadingOdds    = true
        currentMatchOdds = await APIManager.fetchOdds(for: match)
        isLoadingOdds    = false
    }

    // MARK: - Questions
    // Now uses currentMatchOdds (lazily loaded) instead of match.odds

    func getQuestions(for match: Match) -> [Question] {
        let o = currentMatchOdds  // ✅ uses lazily loaded odds
        var q: [Question] = []

        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func ans(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }
        func players(_ list: [PlayerOdd]?, grp: String, limit: Int=12) -> [Answer] {
            (list ?? []).prefix(limit).compactMap { p in
                guard p.odd > 1 else { return nil }
                return Answer(p.name, short:"👤", odds:p.odd, group:"\(grp)_\(p.name)")
            }
        }

        let r=ans([a("\(match.home) Win",short:"HOME",o?.homeWin,"result"),a("Draw",short:"DRAW",o?.draw,"result"),a("\(match.away) Win",short:"AWAY",o?.awayWin,"result")])
        if !r.isEmpty{q.append(Question(category:"⚽ MATCH RESULT",prompt:"Who wins this match?",icon:"trophy",answers:r))}
        let ha=ans([a("\(match.home) to win",short:"HOME",o?.homeWinNoDraw,"ha"),a("\(match.away) to win",short:"AWAY",o?.awayWinNoDraw,"ha")])
        if !ha.isEmpty{q.append(Question(category:"🏆 HOME OR AWAY",prompt:"No draw option",icon:"arrow.left.arrow.right",answers:ha))}
        let dc=ans([a("\(match.home) or Draw",short:"1X",o?.homeOrDraw,"dc"),a("Either team wins",short:"12",o?.homeOrAway,"dc"),a("\(match.away) or Draw",short:"X2",o?.awayOrDraw,"dc")])
        if !dc.isEmpty{q.append(Question(category:"🛡 DOUBLE CHANCE",prompt:"Pick two outcomes",icon:"shield.lefthalf.filled",answers:dc))}
        let dnb=ans([a(match.home,short:"HOME",o?.dnbHome,"dnb"),a(match.away,short:"AWAY",o?.dnbAway,"dnb")])
        if !dnb.isEmpty{q.append(Question(category:"🔄 DRAW NO BET",prompt:"Win or XP back on a draw",icon:"arrow.uturn.left.circle",answers:dnb))}
        let ah=ans([a("\(match.home) -0.5",short:"H-0.5",o?.ahHome05,"ah_h05"),a("\(match.away) -0.5",short:"A-0.5",o?.ahAway05,"ah_a05"),a("\(match.home) -1.5",short:"H-1.5",o?.ahHome15,"ah_h15"),a("\(match.away) -1.5",short:"A-1.5",o?.ahAway15,"ah_a15")])
        if !ah.isEmpty{q.append(Question(category:"⚖️ ASIAN HANDICAP",prompt:"Team with a goal handicap",icon:"scalemass",answers:ah))}
        let goals=ans([a("At least 1",short:"O0.5",o?.over05,"g05"),a("0 goals",short:"U0.5",o?.under05,"g05"),a("2+",short:"O1.5",o?.over15,"g15"),a("0-1",short:"U1.5",o?.under15,"g15"),a("3+",short:"O2.5",o?.over25,"g25"),a("Under 3",short:"U2.5",o?.under25,"g25"),a("4+",short:"O3.5",o?.over35,"g35"),a("Under 4",short:"U3.5",o?.under35,"g35"),a("5+",short:"O4.5",o?.over45,"g45"),a("Under 5",short:"U4.5",o?.under45,"g45")])
        if !goals.isEmpty{q.append(Question(category:"🥅 TOTAL GOALS",prompt:"How many goals in the match?",icon:"soccerball",answers:goals))}
        let exact=ans([a("No goals",short:"0",o?.exactGoals0,"ex0"),a("Exactly 1",short:"1",o?.exactGoals1,"ex1"),a("Exactly 2",short:"2",o?.exactGoals2,"ex2"),a("Exactly 3",short:"3",o?.exactGoals3,"ex3"),a("Exactly 4",short:"4",o?.exactGoals4,"ex4"),a("5+",short:"5+",o?.exactGoals5plus,"ex5")])
        if !exact.isEmpty{q.append(Question(category:"🔢 EXACT GOALS",prompt:"Exact goal count?",icon:"number.circle",answers:exact))}
        let oe=ans([a("Odd goals",short:"ODD",o?.goalsOdd,"goals_oe"),a("Even goals",short:"EVEN",o?.goalsEven,"goals_oe")])
        if !oe.isEmpty{q.append(Question(category:"🎲 GOALS ODD/EVEN",prompt:"Odd or even total?",icon:"dice",answers:oe))}
        let hg=ans([a("\(match.home) 1+",short:"1+",o?.homeOver05,"hg05"),a("\(match.home) 0",short:"0",o?.homeUnder05,"hg05"),a("\(match.home) 2+",short:"2+",o?.homeOver15,"hg15"),a("\(match.home) 3+",short:"3+",o?.homeOver25,"hg25")])
        if !hg.isEmpty{q.append(Question(category:"🏠 \(match.home.uppercased()) GOALS",prompt:"How many does \(match.home) score?",icon:"house.fill",answers:hg))}
        let ag2=ans([a("\(match.away) 1+",short:"1+",o?.awayOver05,"ag05"),a("\(match.away) 0",short:"0",o?.awayUnder05,"ag05"),a("\(match.away) 2+",short:"2+",o?.awayOver15,"ag15"),a("\(match.away) 3+",short:"3+",o?.awayOver25,"ag25")])
        if !ag2.isEmpty{q.append(Question(category:"✈️ \(match.away.uppercased()) GOALS",prompt:"How many does \(match.away) score?",icon:"airplane",answers:ag2))}
        let btts=ans([a("Yes — both score",short:"YES",o?.bttsYes,"btts"),a("No — one blank",short:"NO",o?.bttsNo,"btts")])
        if !btts.isEmpty{q.append(Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both teams score?",icon:"arrow.left.and.right.circle",answers:btts))}
        let bttsW=ans([a("Both score & \(match.home) win",short:"BTTS+H",o?.bttsAndHomeWin,"bttsw"),a("Both score & draw",short:"BTTS+D",o?.bttsAndDraw,"bttsw"),a("Both score & \(match.away) win",short:"BTTS+A",o?.bttsAndAwayWin,"bttsw")])
        if !bttsW.isEmpty{q.append(Question(category:"🔀 BTTS & WINNER",prompt:"Both score — who wins?",icon:"plus.circle",answers:bttsW))}
        let bttsH=ans([a("Both score 1st half",short:"1H",o?.bttsFirstHalf,"btts1h")])
        if !bttsH.isEmpty{q.append(Question(category:"🔀 BTTS FIRST HALF",prompt:"Both score before HT?",icon:"1.circle",answers:bttsH))}
        let bttsS=ans([a("Both score 2nd half",short:"2H",o?.bttsSecondHalf,"btts2h")])
        if !bttsS.isEmpty{q.append(Question(category:"🔀 BTTS SECOND HALF",prompt:"Both score after HT?",icon:"2.circle",answers:bttsS))}
        let ht=ans([a("\(match.home) leading",short:"HOME",o?.htHomeWin,"ht_r"),a("Level at HT",short:"DRAW",o?.htDraw,"ht_r"),a("\(match.away) leading",short:"AWAY",o?.htAwayWin,"ht_r")])
        if !ht.isEmpty{q.append(Question(category:"📊 HALF TIME RESULT",prompt:"Who leads at half time?",icon:"clock",answers:ht))}
        let sh=ans([a("\(match.home) win 2nd half",short:"HOME",o?.shHomeWin,"sh_r"),a("Draw 2nd half",short:"DRAW",o?.shDraw,"sh_r"),a("\(match.away) win 2nd half",short:"AWAY",o?.shAwayWin,"sh_r")])
        if !sh.isEmpty{q.append(Question(category:"📊 SECOND HALF RESULT",prompt:"Who wins the second half?",icon:"clock.arrow.2.circlepath",answers:sh))}
        let htg=ans([a("No 1st half goals",short:"U0.5",o?.htUnder05,"htg05"),a("1+ 1st half goals",short:"O0.5",o?.htOver05,"htg05"),a("2+ 1st half goals",short:"O1.5",o?.htOver15,"htg15")])
        if !htg.isEmpty{q.append(Question(category:"⏱ FIRST HALF GOALS",prompt:"Goals before the break?",icon:"1.circle.fill",answers:htg))}
        let htft=ans([a("Home at HT & FT",short:"H/H",o?.htftHomeHome,"htft_hh"),a("Draw→Home",short:"D/H",o?.htftDrawHome,"htft_dh"),a("Away→Home",short:"A/H",o?.htftAwayHome,"htft_ah"),a("Home→Draw",short:"H/D",o?.htftHomeDraw,"htft_hd"),a("Draw at HT & FT",short:"D/D",o?.htftDrawDraw,"htft_dd"),a("Away→Draw",short:"A/D",o?.htftAwayDraw,"htft_ad"),a("Home→Away",short:"H/A",o?.htftHomeAway,"htft_ha"),a("Draw→Away",short:"D/A",o?.htftDrawAway,"htft_da"),a("Away at HT & FT",short:"A/A",o?.htftAwayAway,"htft_aa")])
        if !htft.isEmpty{q.append(Question(category:"📈 HT / FULL TIME",prompt:"Result at HT and FT?",icon:"arrow.up.right.circle",answers:htft))}
        let fts=ans([a("\(match.home) score first",short:"HOME",o?.firstTeamHome,"fts"),a("\(match.away) score first",short:"AWAY",o?.firstTeamAway,"fts"),a("No goals",short:"NONE",o?.firstTeamNone,"fts")])
        if !fts.isEmpty{q.append(Question(category:"🥇 FIRST TEAM TO SCORE",prompt:"Who opens the scoring?",icon:"flag.checkered",answers:fts))}
        let lts=ans([a("\(match.home) score last",short:"HOME",o?.lastTeamHome,"lts"),a("\(match.away) score last",short:"AWAY",o?.lastTeamAway,"lts")])
        if !lts.isEmpty{q.append(Question(category:"🏁 LAST TEAM TO SCORE",prompt:"Who scores the last goal?",icon:"flag.fill",answers:lts))}
        let wtn=ans([a("\(match.home) win & clean sheet",short:"H-NIL",o?.homeWinToNil,"wtn_h"),a("\(match.away) win & clean sheet",short:"A-NIL",o?.awayWinToNil,"wtn_a")])
        if !wtn.isEmpty{q.append(Question(category:"🔒 WIN TO NIL",prompt:"Win without conceding?",icon:"lock.shield",answers:wtn))}
        let cs=ans([a("\(match.home) clean sheet",short:"HOME",o?.homeCleanSheet,"cs_h"),a("\(match.away) clean sheet",short:"AWAY",o?.awayCleanSheet,"cs_a")])
        if !cs.isEmpty{q.append(Question(category:"🧤 CLEAN SHEET",prompt:"Who keeps a shutout?",icon:"hand.raised.slash",answers:cs))}
        if let scores=o?.correctScores,!scores.isEmpty{q.append(Question(category:"🎯 CORRECT SCORE",prompt:"Exact final score?",icon:"number.circle",answers:scores.map{Answer($0.score,short:$0.score,odds:$0.odd,group:"cs_\($0.score)")}))}
        let wm=ans([a("\(match.home) by 1",short:"H+1",o?.winMarginHome1,"wm"),a("\(match.home) by 2",short:"H+2",o?.winMarginHome2,"wm"),a("\(match.home) by 3+",short:"H+3",o?.winMarginHome3,"wm"),a("\(match.away) by 1",short:"A+1",o?.winMarginAway1,"wm"),a("\(match.away) by 2",short:"A+2",o?.winMarginAway2,"wm"),a("\(match.away) by 3+",short:"A+3",o?.winMarginAway3,"wm"),a("Draw",short:"0",o?.winMarginDraw,"wm")])
        if !wm.isEmpty{q.append(Question(category:"📏 WINNING MARGIN",prompt:"By how many goals?",icon:"ruler",answers:wm))}
        let corners=ans([a("Under 8",short:"U7.5",o?.cornersUnder75,"c75"),a("8+",short:"O7.5",o?.cornersOver75,"c75"),a("9+",short:"O8.5",o?.cornersOver85,"c85"),a("10+",short:"O9.5",o?.cornersOver95,"c95"),a("11+",short:"O10.5",o?.cornersOver105,"c105")])
        if !corners.isEmpty{q.append(Question(category:"🚩 TOTAL CORNERS",prompt:"How many corners?",icon:"flag",answers:corners))}
        let cards=ans([a("Under 2",short:"U1.5",o?.cardsUnder15,"cr15"),a("2+",short:"O1.5",o?.cardsOver15,"cr15"),a("3+",short:"O2.5",o?.cardsOver25,"cr25"),a("4+",short:"O3.5",o?.cardsOver35,"cr35"),a("5+",short:"O4.5",o?.cardsOver45,"cr45")])
        if !cards.isEmpty{q.append(Question(category:"🟨 TOTAL BOOKINGS",prompt:"How many yellow cards?",icon:"rectangle.portrait",answers:cards))}
        let shots=ans([a("Under 9",short:"U8.5",o?.shotsUnder85,"sh85"),a("9+",short:"O8.5",o?.shotsOver85,"sh85"),a("11+",short:"O10.5",o?.shotsOver105,"sh105"),a("13+",short:"O12.5",o?.shotsOver125,"sh125")])
        if !shots.isEmpty{q.append(Question(category:"🎯 TOTAL SHOTS",prompt:"How many shots?",icon:"scope",answers:shots))}
        let any=players(o?.playerAnytime,grp:"any"); if !any.isEmpty{q.append(Question(category:"⚽ ANYTIME GOALSCORER",prompt:"Who scores at any point?",icon:"person.fill.checkmark",answers:any))}
        let first=players(o?.playerFirstGoal,grp:"first"); if !first.isEmpty{q.append(Question(category:"🥇 FIRST GOALSCORER",prompt:"Who opens the scoring?",icon:"1.circle.fill",answers:first))}
        let last=players(o?.playerLastGoal,grp:"last"); if !last.isEmpty{q.append(Question(category:"🏁 LAST GOALSCORER",prompt:"Who scores the final goal?",icon:"flag.checkered",answers:last))}
        let score2=players(o?.playerToBeScored2,grp:"score2"); if !score2.isEmpty{q.append(Question(category:"⚽⚽ SCORE 2+ GOALS",prompt:"Who scores a brace?",icon:"2.circle.fill",answers:score2))}
        let hat=players(o?.playerHatTrick,grp:"hattrick"); if !hat.isEmpty{q.append(Question(category:"🎩 HAT-TRICK",prompt:"Who bags a hat-trick?",icon:"3.circle.fill",answers:hat))}
        let assist=players(o?.playerToAssist,grp:"assist"); if !assist.isEmpty{q.append(Question(category:"🅰️ PLAYER TO ASSIST",prompt:"Who sets up a goal?",icon:"hand.point.right.fill",answers:assist))}
        let carded=players(o?.playerToBeCarded,grp:"card"); if !carded.isEmpty{q.append(Question(category:"🟨 PLAYER BOOKED",prompt:"Who picks up a yellow?",icon:"rectangle.portrait.fill",answers:carded))}
        let fouled=players(o?.playerToBeFouled,grp:"fouled"); if !fouled.isEmpty{q.append(Question(category:"🤕 MOST FOULED PLAYER",prompt:"Who wins the most free kicks?",icon:"figure.fall",answers:fouled))}
        let sot=players(o?.playerShotsOnTarget,grp:"sot"); if !sot.isEmpty{q.append(Question(category:"🎯 SHOTS ON TARGET",prompt:"Who tests the keeper most?",icon:"scope",answers:sot))}

        return q.isEmpty ? fallbackQuestions(for: match) : q
    }

    private func fallbackQuestions(for match: Match) -> [Question] {[
        Question(category:"⚽ MATCH RESULT",prompt:"Who wins?",icon:"trophy",answers:[Answer("\(match.home) Win",short:"HOME",odds:2.10,group:"result"),Answer("Draw",short:"DRAW",odds:3.20,group:"result"),Answer("\(match.away) Win",short:"AWAY",odds:1.90,group:"result")]),
        Question(category:"🥅 TOTAL GOALS",prompt:"How many goals?",icon:"soccerball",answers:[Answer("Under 3",short:"U2.5",odds:2.00,group:"g25"),Answer("3+",short:"O2.5",odds:1.80,group:"g25")]),
        Question(category:"🔀 BOTH TEAMS SCORE?",prompt:"Will both score?",icon:"arrow.left.and.right.circle",answers:[Answer("Yes — both score",short:"YES",odds:2.30,group:"btts"),Answer("No — one blank",short:"NO",odds:1.60,group:"btts")]),
    ]}

    // MARK: - Submit

    func submitPlays(match: Match, myPicksCount: Int) async -> Bool {
        guard !lockedAnswers.isEmpty else { errorMessage = "Lock in at least one answer"; return false }
        guard myPicksCount + lockedAnswers.count <= 5 else { errorMessage = "Max 5 plays per day"; return false }
        isSubmitting = true; errorMessage = nil
        let comboId = isCombo ? UUID().uuidString : nil
        do {
            for answer in lockedAnswers {
                try await supabaseManager.createPick(match:match.displayName, market:answer.label, odds:answer.odds, probability:answer.probability, pointsPossible:answer.xpValue, pointsLost:max(1,answer.xpValue/2), comboId:comboId)
            }
            NotificationManager.shared.scheduleKickoffReminder(for: match)
            clearAnswers(); isSubmitting = false; return true
        } catch { errorMessage = error.localizedDescription; isSubmitting = false; return false }
    }
}
