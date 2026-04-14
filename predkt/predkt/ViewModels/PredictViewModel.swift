import Foundation
import Combine
import Supabase

@MainActor
final class PredictViewModel: ObservableObject {
    
    @Published var matches: [Match] = []
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var isLoading = false
    @Published var isLoadingOdds = false
    @Published var errorMessage: String?
    @Published var isSubmitting = false
    @Published var lockedAnswers: [Answer] = []
    @Published var currentMatchOdds: MatchOdds? = nil
    @Published var groupedMatchesForDate: [(league: String, matches: [Match], isFavourite: Bool)] = []
    @Published var filteredCount: Int = 0
    @Published var favouriteLeagueIds: Set<Int> = []
    @Published var favouriteTeamNames: Set<String> = []
    
    private var matchesLoaded = false
    private var cancellables = Set<AnyCancellable>()
    private var dateChangeTask: Task<Void, Never>?
    private let supabaseManager = SupabaseManager.shared
    
    static let leaguePriority: [String] = [
        "Premier League", "Championship", "Champions League", "Europa League",
        "Conference League", "FA Cup", "EFL Cup", "La Liga", "La Liga 2",
        "Serie A", "Serie B", "Bundesliga", "Bundesliga 2", "Ligue 1",
        "Ligue 2", "Primeira Liga", "Eredivisie",
    ]
    
    // MARK: - Answer / Question
    
    struct Answer: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let shortLabel: String
        let probability: Int
        let odds: Double
        let group: String
        
        var xpValue: Int { max(1, 10 + (100 - probability)) }
        var probabilityDisplay: String { "\(probability)%" }
        var communityPercent: Int { min(92, max(8, probability)) }
        
        static func == (lhs: Answer, rhs: Answer) -> Bool { lhs.id == rhs.id }
        
        init(_ label: String, short: String, odds: Double, group: String) {
            self.label = label
            self.shortLabel = short
            self.odds = odds
            self.group = group
            self.probability = min(99, max(1, Int(round(1.0 / odds * 100))))
        }
    }
    
    struct Question: Identifiable {
        let id = UUID()
        let category: String
        let prompt: String
        let icon: String
        let answers: [Answer]
    }
    
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
    
    func isLocked(_ a: Answer) -> Bool  { lockedAnswers.contains(a) }
    func conflicts(_ a: Answer) -> Bool { lockedAnswers.contains { $0.group == a.group && $0 != a } }
    func clearAnswers() { lockedAnswers = []; currentMatchOdds = nil }
    
    // MARK: - Navigation
    
    func goToNextDay() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        selectedDate = next
        scheduleRegroup()
        APIManager.prefetchOdds(for: matchesForDate(next))
    }
    
    func goToPreviousDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let prev  = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        guard prev >= today else { return }
        selectedDate = prev
        scheduleRegroup()
        APIManager.prefetchOdds(for: matchesForDate(prev))
    }
    
    // MARK: - Date Helpers
    
    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = .current
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private func localDateString(from rawDate: String) -> String {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: rawDate) { return Self.localDateFormatter.string(from: d) }
        
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: rawDate) { return Self.localDateFormatter.string(from: d) }
        
        return String(rawDate.prefix(10))
    }
    
    private var selectedDateString: String {
        Self.localDateFormatter.string(from: selectedDate)
    }
    
    func matchesForDate(_ date: Date) -> [Match] {
        let target = Self.localDateFormatter.string(from: date)
        return matches.filter { localDateString(from: $0.rawDate) == target }
    }
    
    var datesWithMatches: Set<String> {
        Set(matches.map { localDateString(from: $0.rawDate) })
    }
    
    func hasMatches(on date: Date) -> Bool {
        datesWithMatches.contains(Self.localDateFormatter.string(from: date))
    }
    
    func isFavouriteMatch(_ match: Match) -> Bool {
        favouriteLeagueIds.contains(match.leagueId)
        || favouriteTeamNames.contains(match.home)
        || favouriteTeamNames.contains(match.away)
    }
    
    // MARK: - Background Regroup
    
    func scheduleRegroupPublic() { scheduleRegroup() }
    
    private func scheduleRegroup() {
        dateChangeTask?.cancel()
        dateChangeTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
            guard !Task.isCancelled else { return }
            await regroup()
        }
    }
    
    private func regroup() async {
        // Capture values before going off-main
        let target     = selectedDateString
        let allMatches = matches
        let favLeagues = favouriteLeagueIds
        let favTeams   = favouriteTeamNames
        let priority   = Self.leaguePriority
        
        // Run the heavy filtering + sorting on a background thread
        let grouped = await withCheckedContinuation {
            (continuation: CheckedContinuation<[(league: String, matches: [Match], isFavourite: Bool)], Never>) in
            
            DispatchQueue.global(qos: .userInitiated).async {
                
                // Date parsing helpers (recreated inside closure — no self needed)
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.timeZone   = .current
                fmt.locale     = Locale(identifier: "en_US_POSIX")
                
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                
                func dateStr(_ raw: String) -> String {
                    if let d = f1.date(from: raw) { return fmt.string(from: d) }
                    if let d = f2.date(from: raw) { return fmt.string(from: d) }
                    return String(raw.prefix(10))
                }
                
                func isFav(_ m: Match) -> Bool {
                    favLeagues.contains(m.leagueId)
                    || favTeams.contains(m.home)
                    || favTeams.contains(m.away)
                }
                
                // Filter to selected date
                let filtered = allMatches.filter { dateStr($0.rawDate) == target }
                
                // Group by competition
                var order: [String] = []
                var groups: [String: [Match]] = [:]
                var leagueFav: [String: Bool] = [:]
                
                for match in filtered {
                    if groups[match.competition] == nil {
                        order.append(match.competition)
                        groups[match.competition] = []
                    }
                    groups[match.competition]!.append(match)
                    if leagueFav[match.competition] == nil || leagueFav[match.competition] == false {
                        leagueFav[match.competition] = isFav(match)
                    }
                }
                
                // Sort leagues: favourites first, then by priority list, then alphabetically
                order.sort { a, b in
                    let af = leagueFav[a] ?? false
                    let bf = leagueFav[b] ?? false
                    if af != bf { return af }
                    let ai = priority.firstIndex(of: a)
                    let bi = priority.firstIndex(of: b)
                    switch (ai, bi) {
                    case let (.some(x), .some(y)): return x < y
                    case (.some, .none):           return true
                    case (.none, .some):           return false
                    case (.none, .none):           return a < b
                    }
                }
                
                // Sort matches within each league
                let result: [(league: String, matches: [Match], isFavourite: Bool)] = order.map { league in
                    let sorted = groups[league]!.sorted { a, b in
                        let af = isFav(a)
                        let bf = isFav(b)
                        if af != bf { return af }
                        if a.isLive != b.isLive { return a.isLive }
                        return a.rawDate < b.rawDate
                    }
                    return (league: league, matches: sorted, isFavourite: leagueFav[league] ?? false)
                }
                
                continuation.resume(returning: result)
            }
        }
        
        // Publish on main thread
        groupedMatchesForDate = grouped
        filteredCount = grouped.reduce(0) { $0 + $1.matches.count }
    }
    
    // MARK: - Init
    
    init() {
        NotificationCenter.default.publisher(for: .matchesRefreshed)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let fresh = notification.object as? [Match] else { return }
                self.matches = fresh
                self.scheduleRegroup()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Load
    
    func loadMatches() async {
        guard !matchesLoaded else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let matchFetch   = APIManager.fetchAllMatches()
            async let profileFetch = supabaseManager.fetchUserProfile()
            let (fetchedMatches, profile) = try await (matchFetch, profileFetch)
            
            matches       = fetchedMatches
            matchesLoaded = true
            
            if let s = profile?.favourite_league, !s.isEmpty {
                favouriteLeagueIds = Set(
                    s.components(separatedBy: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                )
            }
            if let s = profile?.favourite_team, !s.isEmpty {
                favouriteTeamNames = Set(
                    s.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                )
            }
            
            // Auto-advance to first day with matches if today is empty
            if !datesWithMatches.contains(selectedDateString) {
                let cal = Calendar.current
                for i in 0..<30 {
                    guard let d = cal.date(byAdding: .day, value: i, to: selectedDate),
                          hasMatches(on: d) else { continue }
                    selectedDate = d
                    break
                }
            }
            
            await regroup()
            APIManager.prefetchOdds(for: matchesForDate(selectedDate))
            
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func refreshMatches() async {
        matchesLoaded = false
        matches = []
        isLoading = true
        groupedMatchesForDate = []
        filteredCount = 0
        do {
            matches       = try await APIManager.forceRefresh()
            matchesLoaded = true
            if !datesWithMatches.contains(selectedDateString) {
                let cal = Calendar.current
                for i in 0..<30 {
                    guard let d = cal.date(byAdding: .day, value: i, to: selectedDate),
                          hasMatches(on: d) else { continue }
                    selectedDate = d
                    break
                }
            }
            await regroup()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func loadOdds(for match: Match) async {
        currentMatchOdds = nil
        guard !match.isLive, !match.isFinished else { return }
        isLoadingOdds    = true
        currentMatchOdds = await APIManager.fetchOdds(for: match)
        isLoadingOdds    = false
    }
    
    // MARK: - Questions
    
    func getQuestions(for match: Match) -> [Question] {
        let o = currentMatchOdds
        var q: [Question] = []
        
        func a(_ label: String, short: String, _ odd: Double?, _ group: String) -> Answer? {
            guard let odd = odd, odd > 1.0 else { return nil }
            return Answer(label, short: short, odds: odd, group: group)
        }
        func ans(_ items: [Answer?]) -> [Answer] { items.compactMap { $0 } }
        func players(_ list: [PlayerOdd]?, grp: String, limit: Int = 14) -> [Answer] {
            guard let list = list else { return [] }
            // Sort by odds ascending (lowest odds = most likely = shown first)
            let sorted = list.sorted { $0.odd < $1.odd }
            return sorted.prefix(limit).compactMap { p in
                guard p.odd > 1, !p.name.isEmpty else { return nil }
                // ✅ short = player name so locked banner shows "Haaland" not "👤"
                let shortName = p.name.components(separatedBy: " ").last ?? p.name
                return Answer(p.name, short: shortName, odds: p.odd, group: "\(grp)_\(p.name)")
            }
        }
        
        // ── 1. MAIN MATCH MARKETS ────────────────────────────────────────────
        
        let r = ans([
            a("\(match.home) Win", short: "HOME", o?.homeWin, "result"),
            a("Draw",              short: "DRAW", o?.draw,    "result"),
            a("\(match.away) Win", short: "AWAY", o?.awayWin, "result"),
        ])
        if !r.isEmpty {
            q.append(Question(category: "⚽ FULL-TIME RESULT", prompt: "Who wins at full time?", icon: "trophy", answers: r))
        }
        
        let ha = ans([
            a("\(match.home) to win", short: "HOME", o?.homeWinNoDraw, "ha"),
            a("\(match.away) to win", short: "AWAY", o?.awayWinNoDraw, "ha"),
        ])
        if !ha.isEmpty {
            q.append(Question(category: "🏆 HOME OR AWAY", prompt: "Who wins? No draw option.", icon: "arrow.left.arrow.right", answers: ha))
        }
        
        let dc = ans([
            a("\(match.home) or Draw", short: "1X", o?.homeOrDraw, "dc"),
            a("Either team wins",      short: "12", o?.homeOrAway, "dc"),
            a("\(match.away) or Draw", short: "X2", o?.awayOrDraw, "dc"),
        ])
        if !dc.isEmpty {
            q.append(Question(category: "🛡 DOUBLE CHANCE", prompt: "Cover two of the three outcomes", icon: "shield.lefthalf.filled", answers: dc))
        }
        
        let dnb = ans([
            a(match.home, short: "HOME", o?.dnbHome, "dnb"),
            a(match.away, short: "AWAY", o?.dnbAway, "dnb"),
        ])
        if !dnb.isEmpty {
            q.append(Question(category: "🔄 DRAW NO BET", prompt: "Win or get XP back if it's a draw", icon: "arrow.uturn.left.circle", answers: dnb))
        }
        
        let ah = ans([
            a("\(match.home) −0.5", short: "H−0.5", o?.ahHome05, "ah_h05"),
            a("\(match.away) −0.5", short: "A−0.5", o?.ahAway05, "ah_a05"),
            a("\(match.home) −1.5", short: "H−1.5", o?.ahHome15, "ah_h15"),
            a("\(match.away) −1.5", short: "A−1.5", o?.ahAway15, "ah_a15"),
        ])
        if !ah.isEmpty {
            q.append(Question(category: "⚖️ ASIAN HANDICAP", prompt: "Adjusted result — no draw possible", icon: "scalemass", answers: ah))
        }
        
        let wm = ans([
            a("\(match.home) win by 1",  short: "H+1", o?.winMarginHome1, "wm"),
            a("\(match.home) win by 2",  short: "H+2", o?.winMarginHome2, "wm"),
            a("\(match.home) win by 3+", short: "H+3", o?.winMarginHome3, "wm"),
            a("\(match.away) win by 1",  short: "A+1", o?.winMarginAway1, "wm"),
            a("\(match.away) win by 2",  short: "A+2", o?.winMarginAway2, "wm"),
            a("\(match.away) win by 3+", short: "A+3", o?.winMarginAway3, "wm"),
            a("Draw",                    short: "0",   o?.winMarginDraw,  "wm"),
        ])
        if !wm.isEmpty {
            q.append(Question(category: "📏 WINNING MARGIN", prompt: "By how many goals does a team win?", icon: "ruler", answers: wm))
        }
        
        let wtn = ans([
            a("\(match.home) win & clean sheet", short: "H−NIL", o?.homeWinToNil, "wtn_h"),
            a("\(match.away) win & clean sheet", short: "A−NIL", o?.awayWinToNil, "wtn_a"),
        ])
        if !wtn.isEmpty {
            q.append(Question(category: "🔒 WIN TO NIL", prompt: "A team wins without conceding", icon: "lock.shield", answers: wtn))
        }
        
        // ── 2. GOALS & SCORE MARKETS ─────────────────────────────────────────
        
        let goals = ans([
            a("Under 0.5 goals", short: "U0.5", o?.under05, "g05"),
            a("Over 0.5 goals",  short: "O0.5", o?.over05,  "g05"),
            a("Under 1.5 goals", short: "U1.5", o?.under15, "g15"),
            a("Over 1.5 goals",  short: "O1.5", o?.over15,  "g15"),
            a("Under 2.5 goals", short: "U2.5", o?.under25, "g25"),
            a("Over 2.5 goals",  short: "O2.5", o?.over25,  "g25"),
            a("Under 3.5 goals", short: "U3.5", o?.under35, "g35"),
            a("Over 3.5 goals",  short: "O3.5", o?.over35,  "g35"),
            a("Under 4.5 goals", short: "U4.5", o?.under45, "g45"),
            a("Over 4.5 goals",  short: "O4.5", o?.over45,  "g45"),
        ])
        if !goals.isEmpty {
            q.append(Question(category: "🥅 TOTAL GOALS — OVER/UNDER", prompt: "Choose a goal line for the full match", icon: "soccerball", answers: goals))
        }
        
        let exact = ans([
            a("No goals (0)", short: "0",  o?.exactGoals0,    "ex"),
            a("Exactly 1",    short: "1",  o?.exactGoals1,    "ex"),
            a("Exactly 2",    short: "2",  o?.exactGoals2,    "ex"),
            a("Exactly 3",    short: "3",  o?.exactGoals3,    "ex"),
            a("Exactly 4",    short: "4",  o?.exactGoals4,    "ex"),
            a("5 or more",    short: "5+", o?.exactGoals5plus,"ex"),
        ])
        if !exact.isEmpty {
            q.append(Question(category: "🔢 EXACT NUMBER OF GOALS", prompt: "How many goals will be scored in total?", icon: "number.circle", answers: exact))
        }
        
        let oe = ans([
            a("Odd total goals",  short: "ODD",  o?.goalsOdd,  "goals_oe"),
            a("Even total goals", short: "EVEN", o?.goalsEven, "goals_oe"),
        ])
        if !oe.isEmpty {
            q.append(Question(category: "🎲 GOALS — ODD OR EVEN", prompt: "Will total goals be odd or even?", icon: "dice", answers: oe))
        }
        
        if let scores = o?.correctScores, !scores.isEmpty {
            let csAns = scores.map { Answer($0.score, short: $0.score, odds: $0.odd, group: "cs_\($0.score)") }
            q.append(Question(category: "🎯 CORRECT SCORE — FULL TIME", prompt: "What's the exact final scoreline?", icon: "number.circle", answers: csAns))
        }
        
        let htft = ans([
            a("Home at HT & FT",   short: "H/H", o?.htftHomeHome, "htft_hh"),
            a("Draw → Home win",   short: "D/H", o?.htftDrawHome, "htft_dh"),
            a("Away → Home win",   short: "A/H", o?.htftAwayHome, "htft_ah"),
            a("Home → Draw",       short: "H/D", o?.htftHomeDraw, "htft_hd"),
            a("Draw at HT & FT",   short: "D/D", o?.htftDrawDraw, "htft_dd"),
            a("Away → Draw",       short: "A/D", o?.htftAwayDraw, "htft_ad"),
            a("Home → Away win",   short: "H/A", o?.htftHomeAway, "htft_ha"),
            a("Draw → Away win",   short: "D/A", o?.htftDrawAway, "htft_da"),
            a("Away at HT & FT",   short: "A/A", o?.htftAwayAway, "htft_aa"),
        ])
        if !htft.isEmpty {
            q.append(Question(category: "📈 HALF-TIME / FULL-TIME", prompt: "Pick the result at the break AND at full time", icon: "arrow.up.right.circle", answers: htft))
        }
        
        // ── 3. HALF-TIME SPECIFIC MARKETS ────────────────────────────────────
        
        let ht = ans([
            a("\(match.home) lead at HT", short: "HOME", o?.htHomeWin, "ht_r"),
            a("Level at half time",       short: "DRAW", o?.htDraw,    "ht_r"),
            a("\(match.away) lead at HT", short: "AWAY", o?.htAwayWin, "ht_r"),
        ])
        if !ht.isEmpty {
            q.append(Question(category: "📊 FIRST HALF — RESULT", prompt: "Who's ahead at the break?", icon: "clock", answers: ht))
        }
        
        let sh = ans([
            a("\(match.home) win 2nd half", short: "HOME", o?.shHomeWin, "sh_r"),
            a("Draw in 2nd half",           short: "DRAW", o?.shDraw,    "sh_r"),
            a("\(match.away) win 2nd half", short: "AWAY", o?.shAwayWin, "sh_r"),
        ])
        if !sh.isEmpty {
            q.append(Question(category: "📊 SECOND HALF — RESULT", prompt: "Who wins just the second half?", icon: "clock.arrow.2.circlepath", answers: sh))
        }
        
        let htg = ans([
            a("Under 0.5 goals before HT", short: "U0.5", o?.htUnder05, "htg05"),
            a("Over 0.5 goals before HT",  short: "O0.5", o?.htOver05,  "htg05"),
            a("Under 1.5 goals before HT", short: "U1.5", o?.htUnder15, "htg15"),
            a("Over 1.5 goals before HT",  short: "O1.5", o?.htOver15,  "htg15"),
        ])
        if !htg.isEmpty {
            q.append(Question(category: "⏱ FIRST HALF — GOALS", prompt: "Goals before the half-time whistle", icon: "1.circle.fill", answers: htg))
        }
        
        if let scores = o?.correctScoresHT, !scores.isEmpty {
            let csAns = scores.map { Answer("HT: \($0.score)", short: $0.score, odds: $0.odd, group: "cs_ht_\($0.score)") }
            q.append(Question(category: "🎯 CORRECT SCORE — HALF TIME", prompt: "What's the scoreline at the break?", icon: "number.square", answers: csAns))
        }
        
        if let scores = o?.correctScoresSH, !scores.isEmpty {
            let csAns = scores.map { Answer("2H: \($0.score)", short: $0.score, odds: $0.odd, group: "cs_sh_\($0.score)") }
            q.append(Question(category: "🎯 CORRECT SCORE — 2ND HALF", prompt: "Goals scored in the second half only", icon: "number.square.fill", answers: csAns))
        }
        
        // ── 4. BOTH TEAMS TO SCORE ────────────────────────────────────────────
        
        let btts = ans([
            a("Yes — both teams score",       short: "YES", o?.bttsYes, "btts"),
            a("No — at least one team blank", short: "NO",  o?.bttsNo,  "btts"),
        ])
        if !btts.isEmpty {
            q.append(Question(category: "🔀 BOTH TEAMS TO SCORE", prompt: "Do both sides get on the scoresheet?", icon: "arrow.left.and.right.circle", answers: btts))
        }
        
        let bttsW = ans([
            a("Both score & \(match.home) win", short: "BTTS+H", o?.bttsAndHomeWin, "bttsw"),
            a("Both score & draw",              short: "BTTS+D", o?.bttsAndDraw,    "bttsw"),
            a("Both score & \(match.away) win", short: "BTTS+A", o?.bttsAndAwayWin, "bttsw"),
        ])
        if !bttsW.isEmpty {
            q.append(Question(category: "🔀 BTTS & WINNER", prompt: "Both score — but who takes the points?", icon: "plus.circle", answers: bttsW))
        }
        
        let bttsH = ans([
            a("Both score in the first half", short: "1H YES", o?.bttsFirstHalf, "btts1h"),
        ])
        if !bttsH.isEmpty {
            q.append(Question(category: "🔀 BTTS — FIRST HALF", prompt: "Do both teams score before half time?", icon: "1.circle", answers: bttsH))
        }
        
        let bttsS = ans([
            a("Both score in the second half", short: "2H YES", o?.bttsSecondHalf, "btts2h"),
        ])
        if !bttsS.isEmpty {
            q.append(Question(category: "🔀 BTTS — SECOND HALF", prompt: "Do both teams score after half time?", icon: "2.circle", answers: bttsS))
        }
        
        let bttsBH = ans([
            a("Both teams score in BOTH halves", short: "BOTH", o?.bttsBothHalves, "btts_bh"),
        ])
        if !bttsBH.isEmpty {
            q.append(Question(category: "🔀 BTTS — BOTH HALVES", prompt: "Both teams score in each half?", icon: "arrow.left.and.right", answers: bttsBH))
        }
        
        let sbh = ans([
            a("\(match.home) score in both halves", short: "H BOTH", o?.homeScoreBothHalves, "sbh_h"),
            a("\(match.away) score in both halves", short: "A BOTH", o?.awayScoreBothHalves, "sbh_a"),
        ])
        if !sbh.isEmpty {
            q.append(Question(category: "🔁 SCORE IN BOTH HALVES", prompt: "Does one team score in each half?", icon: "arrow.triangle.2.circlepath", answers: sbh))
        }
        
        // ── 5. TEAM PERFORMANCE ───────────────────────────────────────────────
        
        let cs = ans([
            a("\(match.home) keep a clean sheet", short: "HOME", o?.homeCleanSheet, "cs_h"),
            a("\(match.away) keep a clean sheet", short: "AWAY", o?.awayCleanSheet, "cs_a"),
        ])
        if !cs.isEmpty {
            q.append(Question(category: "🧤 CLEAN SHEET", prompt: "Which keeper keeps a shutout?", icon: "hand.raised.slash", answers: cs))
        }
        
        let fts = ans([
            a("\(match.home) score first", short: "HOME", o?.firstTeamHome, "fts"),
            a("\(match.away) score first", short: "AWAY", o?.firstTeamAway, "fts"),
            a("No goals in the match",     short: "NONE", o?.firstTeamNone, "fts"),
        ])
        if !fts.isEmpty {
            q.append(Question(category: "🥇 FIRST TEAM TO SCORE", prompt: "Who opens the scoring?", icon: "flag.checkered", answers: fts))
        }
        
        let lts = ans([
            a("\(match.home) score last", short: "HOME", o?.lastTeamHome, "lts"),
            a("\(match.away) score last", short: "AWAY", o?.lastTeamAway, "lts"),
        ])
        if !lts.isEmpty {
            q.append(Question(category: "🏁 LAST TEAM TO SCORE", prompt: "Who gets the final goal?", icon: "flag.fill", answers: lts))
        }
        
        let hg = ans([
            a("\(match.home) score 1+", short: "1+", o?.homeOver05,  "hg05"),
            a("\(match.home) score 0",  short: "0",  o?.homeUnder05, "hg05"),
            a("\(match.home) score 2+", short: "2+", o?.homeOver15,  "hg15"),
            a("\(match.home) under 2",  short: "U2", o?.homeUnder15, "hg15"),
            a("\(match.home) score 3+", short: "3+", o?.homeOver25,  "hg25"),
        ])
        if !hg.isEmpty {
            q.append(Question(category: "🏠 \(match.home.uppercased()) — GOALS", prompt: "How many does \(match.home) score?", icon: "house.fill", answers: hg))
        }
        
        let ag2 = ans([
            a("\(match.away) score 1+", short: "1+", o?.awayOver05,  "ag05"),
            a("\(match.away) score 0",  short: "0",  o?.awayUnder05, "ag05"),
            a("\(match.away) score 2+", short: "2+", o?.awayOver15,  "ag15"),
            a("\(match.away) under 2",  short: "U2", o?.awayUnder15, "ag15"),
            a("\(match.away) score 3+", short: "3+", o?.awayOver25,  "ag25"),
        ])
        if !ag2.isEmpty {
            q.append(Question(category: "✈️ \(match.away.uppercased()) — GOALS", prompt: "How many does \(match.away) score?", icon: "airplane", answers: ag2))
        }
        
        // ── 6. CORNERS ────────────────────────────────────────────────────────
        
        let corners = ans([
            a("Under 7.5 corners",  short: "U7.5",  o?.cornersUnder75,  "c75"),
            a("Over 7.5 corners",   short: "O7.5",  o?.cornersOver75,   "c75"),
            a("Under 8.5 corners",  short: "U8.5",  o?.cornersUnder85,  "c85"),
            a("Over 8.5 corners",   short: "O8.5",  o?.cornersOver85,   "c85"),
            a("Under 9.5 corners",  short: "U9.5",  o?.cornersUnder95,  "c95"),
            a("Over 9.5 corners",   short: "O9.5",  o?.cornersOver95,   "c95"),
            a("Under 10.5 corners", short: "U10.5", o?.cornersUnder105, "c105"),
            a("Over 10.5 corners",  short: "O10.5", o?.cornersOver105,  "c105"),
        ])
        if !corners.isEmpty {
            q.append(Question(category: "🚩 CORNERS — TOTAL", prompt: "How many corners in the full match?", icon: "flag", answers: corners))
        }
        
        let htc = ans([
            a("Under 3.5 HT corners", short: "U3.5", o?.htCornersUnder35, "htc35"),
            a("Over 3.5 HT corners",  short: "O3.5", o?.htCornersOver35,  "htc35"),
            a("Under 4.5 HT corners", short: "U4.5", o?.htCornersUnder45, "htc45"),
            a("Over 4.5 HT corners",  short: "O4.5", o?.htCornersOver45,  "htc45"),
        ])
        if !htc.isEmpty {
            q.append(Question(category: "🚩 CORNERS — FIRST HALF", prompt: "How many corners before the break?", icon: "flag.fill", answers: htc))
        }
        
        // ── 7. CARDS / BOOKINGS ───────────────────────────────────────────────
        
        let cards = ans([
            a("Under 1.5 cards", short: "U1.5", o?.cardsUnder15, "cr15"),
            a("Over 1.5 cards",  short: "O1.5", o?.cardsOver15,  "cr15"),
            a("Under 2.5 cards", short: "U2.5", o?.cardsUnder25, "cr25"),
            a("Over 2.5 cards",  short: "O2.5", o?.cardsOver25,  "cr25"),
            a("Under 3.5 cards", short: "U3.5", o?.cardsUnder35, "cr35"),
            a("Over 3.5 cards",  short: "O3.5", o?.cardsOver35,  "cr35"),
            a("Under 4.5 cards", short: "U4.5", o?.cardsUnder45, "cr45"),
            a("Over 4.5 cards",  short: "O4.5", o?.cardsOver45,  "cr45"),
        ])
        if !cards.isEmpty {
            q.append(Question(category: "🟨 BOOKINGS — TOTAL CARDS", prompt: "How many yellow cards will be shown?", icon: "rectangle.portrait", answers: cards))
        }
        
        let shots = ans([
            a("Under 8.5 shots",  short: "U8.5",  o?.shotsUnder85,  "sh85"),
            a("Over 8.5 shots",   short: "O8.5",  o?.shotsOver85,   "sh85"),
            a("Under 10.5 shots", short: "U10.5", o?.shotsUnder105, "sh105"),
            a("Over 10.5 shots",  short: "O10.5", o?.shotsOver105,  "sh105"),
            a("Under 12.5 shots", short: "U12.5", o?.shotsUnder125, "sh125"),
            a("Over 12.5 shots",  short: "O12.5", o?.shotsOver125,  "sh125"),
        ])
        if !shots.isEmpty {
            q.append(Question(category: "🎯 SHOTS — TOTAL", prompt: "How many shots are taken in the match?", icon: "scope", answers: shots))
        }
        
        // ── 8. PLAYER PROPS ───────────────────────────────────────────────────
        
        let any = players(o?.playerAnytime, grp: "any")
        if !any.isEmpty {
            q.append(Question(category: "⚽ ANYTIME GOALSCORER", prompt: "Which player scores at any point?", icon: "person.fill.checkmark", answers: any))
        }
        
        let first = players(o?.playerFirstGoal, grp: "first")
        if !first.isEmpty {
            q.append(Question(category: "🥇 FIRST GOALSCORER", prompt: "Who opens the scoring?", icon: "1.circle.fill", answers: first))
        }
        
        let last = players(o?.playerLastGoal, grp: "last")
        if !last.isEmpty {
            q.append(Question(category: "🏁 LAST GOALSCORER", prompt: "Who scores the final goal?", icon: "flag.checkered", answers: last))
        }
        
        let score2 = players(o?.playerToBeScored2, grp: "score2")
        if !score2.isEmpty {
            q.append(Question(category: "⚽⚽ PLAYER TO SCORE 2+", prompt: "Who scores a brace or more?", icon: "2.circle.fill", answers: score2))
        }
        
        let hat = players(o?.playerHatTrick, grp: "hattrick")
        if !hat.isEmpty {
            q.append(Question(category: "🎩 PLAYER TO SCORE HAT-TRICK", prompt: "Who completes a hat-trick?", icon: "3.circle.fill", answers: hat))
        }
        
        let assist = players(o?.playerToAssist, grp: "assist")
        if !assist.isEmpty {
            q.append(Question(category: "🅰️ PLAYER TO ASSIST", prompt: "Who creates a goal with an assist?", icon: "hand.point.right.fill", answers: assist))
        }
        
        let carded = players(o?.playerToBeCarded, grp: "card")
        if !carded.isEmpty {
            q.append(Question(category: "🟨 PLAYER TO BE BOOKED", prompt: "Which player receives a yellow card?", icon: "rectangle.portrait.fill", answers: carded))
        }
        
        let sot = players(o?.playerShotsOnTarget, grp: "sot")
        if !sot.isEmpty {
            q.append(Question(category: "🎯 PLAYER SHOTS ON TARGET", prompt: "Who tests the keeper most?", icon: "scope", answers: sot))
        }
        
        let fouled = players(o?.playerToBeFouled, grp: "fouled")
        if !fouled.isEmpty {
            q.append(Question(category: "🤕 PLAYER TO BE FOULED MOST", prompt: "Who wins the most free kicks?", icon: "figure.fall", answers: fouled))
        }
        
        return q.isEmpty ? fallbackQuestions(for: match) : q
    }
    
    // MARK: - Fallback Questions
    
    private func fallbackQuestions(for match: Match) -> [Question] {
        return [
            Question(
                category: "⚽ FULL-TIME RESULT",
                prompt: "Who wins at full time?",
                icon: "trophy",
                answers: [
                    Answer("\(match.home) Win", short: "HOME", odds: 2.10, group: "result"),
                    Answer("Draw",              short: "DRAW", odds: 3.20, group: "result"),
                    Answer("\(match.away) Win", short: "AWAY", odds: 1.90, group: "result"),
                ]
            ),
            Question(
                category: "🥅 TOTAL GOALS",
                prompt: "Over or under 2.5 goals?",
                icon: "soccerball",
                answers: [
                    Answer("Under 2.5 goals", short: "U2.5", odds: 2.00, group: "g25"),
                    Answer("Over 2.5 goals",  short: "O2.5", odds: 1.80, group: "g25"),
                ]
            ),
            Question(
                category: "🔀 BOTH TEAMS TO SCORE",
                prompt: "Do both teams score?",
                icon: "arrow.left.and.right.circle",
                answers: [
                    Answer("Yes — both score",        short: "YES", odds: 2.30, group: "btts"),
                    Answer("No — at least one blank", short: "NO",  odds: 1.60, group: "btts"),
                ]
            ),
            Question(
                category: "📊 FIRST HALF — RESULT",
                prompt: "Who leads at half time?",
                icon: "clock",
                answers: [
                    Answer("\(match.home) leading", short: "HOME", odds: 2.60, group: "ht_r"),
                    Answer("Level at HT",           short: "DRAW", odds: 2.10, group: "ht_r"),
                    Answer("\(match.away) leading", short: "AWAY", odds: 3.50, group: "ht_r"),
                ]
            ),
        ]
    }
    
    // MARK: - Submit
    
    func submitPlays(match: Match, myPicksCount: Int) async -> Bool {
        guard !lockedAnswers.isEmpty else {
            errorMessage = "Lock in at least one answer"
            return false
        }
        
        // myPicksCount = number of distinct matches predicted today
        // Allow unlimited picks per match, but max 5 different matches
        let currentPicks = (try? await supabaseManager.fetchMyPicks()) ?? []
        let predictedMatchNames = Set(currentPicks.map { $0.match })
        let isNewMatch = !predictedMatchNames.contains(match.displayName)
        
        if isNewMatch && predictedMatchNames.count >= 5 {
            errorMessage = "You can predict on up to 5 matches per day"
            return false
        }
        
        isSubmitting = true
        errorMessage = nil
        let comboId = isCombo ? UUID().uuidString : nil
        do {
            for answer in lockedAnswers {
                try await supabaseManager.createPick(
                    match:          match.displayName,
                    market:         answer.label,
                    odds:           answer.odds,
                    probability:    answer.probability,
                    pointsPossible: answer.xpValue,
                    pointsLost:     max(1, answer.xpValue / 2),
                    comboId:        comboId
                )
            }
            NotificationManager.shared.scheduleKickoffReminder(for: match)
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
