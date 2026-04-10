import Foundation
import Combine

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedMatch: Match?
    @Published var isSubmitting = false
    @Published var selectedMarkets: [Market] = []

    private var matchesLoaded = false
    private let supabaseManager = SupabaseManager.shared
    private let topLeagueIDs = [39, 140, 135, 78, 61, 94, 88, 2, 3]

    // MARK: - Market Model

    struct Market: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let sublabel: String?   // e.g. player name for props
        let probability: Int
        let odds: Double
        let group: String       // conflict group

        var pointsValue: Int { max(1, 10 + (100 - probability)) }
        var probabilityDisplay: String { "\(probability)%" }
        static func == (lhs: Market, rhs: Market) -> Bool { lhs.id == rhs.id }

        init(_ label: String, odds: Double, group: String, sublabel: String? = nil) {
            self.label      = label
            self.sublabel   = sublabel
            self.odds       = odds
            self.group      = group
            self.probability = min(99, max(1, Int(round(1.0 / odds * 100))))
        }
    }

    // MARK: - Market Groups

    struct MarketGroup: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let markets: [Market]
        var isEmpty: Bool { markets.isEmpty }
    }

    func getMarketGroups(for match: Match) -> [MarketGroup] {
        let o = match.odds
        var groups: [MarketGroup] = []

        // Helper: only include market if odds exist
        func m(_ label: String, _ odd: Double?, _ group: String, sub: String? = nil) -> Market? {
            guard let odd, odd > 1.0 else { return nil }
            return Market(label, odds: odd, group: group, sublabel: sub)
        }
        func markets(_ items: [Market?]) -> [Market] { items.compactMap { $0 } }

        // 1. Match Result
        groups.append(MarketGroup(title: "Match Result", icon: "trophy", markets: markets([
            m("Home Win",  o?.homeWin,  "result"),
            m("Draw",      o?.draw,     "result"),
            m("Away Win",  o?.awayWin,  "result"),
        ])))

        // 2. Double Chance
        groups.append(MarketGroup(title: "Double Chance", icon: "shield.lefthalf.filled", markets: markets([
            m("\(match.home) or Draw", o?.homeOrDraw, "dc"),
            m("\(match.away) or Draw", o?.awayOrDraw, "dc"),
            m("\(match.home) or \(match.away)", o?.homeOrAway, "dc"),
        ])))

        // 3. Draw No Bet
        groups.append(MarketGroup(title: "Draw No Bet", icon: "arrow.left.arrow.right", markets: markets([
            m(match.home, o?.dnbHome, "dnb"),
            m(match.away, o?.dnbAway, "dnb"),
        ])))

        // 4. Half Time Result
        groups.append(MarketGroup(title: "Half Time Result", icon: "clock", markets: markets([
            m("Home Win", o?.htHomeWin, "ht_result"),
            m("Draw",     o?.htDraw,    "ht_result"),
            m("Away Win", o?.htAwayWin, "ht_result"),
        ])))

        // 5. Goals Over/Under (show most popular lines)
        let goalMarkets: [Market?] = [
            m("Over 0.5",  o?.over05,  "goals_05"),
            m("Under 0.5", o?.under05, "goals_05"),
            m("Over 1.5",  o?.over15,  "goals_15"),
            m("Under 1.5", o?.under15, "goals_15"),
            m("Over 2.5",  o?.over25,  "goals_25"),
            m("Under 2.5", o?.under25, "goals_25"),
            m("Over 3.5",  o?.over35,  "goals_35"),
            m("Under 3.5", o?.under35, "goals_35"),
            m("Over 4.5",  o?.over45,  "goals_45"),
            m("Under 4.5", o?.under45, "goals_45"),
        ]
        groups.append(MarketGroup(title: "Goals Over/Under", icon: "soccerball", markets: markets(goalMarkets)))

        // 6. First Half Goals
        groups.append(MarketGroup(title: "First Half Goals", icon: "1.circle", markets: markets([
            m("Over 0.5",  o?.htOver05,  "ht_goals_05"),
            m("Under 0.5", o?.htUnder05, "ht_goals_05"),
            m("Over 1.5",  o?.htOver15,  "ht_goals_15"),
            m("Under 1.5", o?.htUnder15, "ht_goals_15"),
        ])))

        // 7. Both Teams to Score
        groups.append(MarketGroup(title: "Both Teams to Score", icon: "arrow.left.and.right.circle", markets: markets([
            m("Yes", o?.bttsYes, "btts"),
            m("No",  o?.bttsNo,  "btts"),
        ])))

        // 8. Corners
        let cornerMarkets: [Market?] = [
            m("Over 7.5",  o?.cornersOver75,  "corners_75"),
            m("Under 7.5", o?.cornersUnder75, "corners_75"),
            m("Over 8.5",  o?.cornersOver85,  "corners_85"),
            m("Under 8.5", o?.cornersUnder85, "corners_85"),
            m("Over 9.5",  o?.cornersOver95,  "corners_95"),
            m("Under 9.5", o?.cornersUnder95, "corners_95"),
            m("Over 10.5",  o?.cornersOver105,  "corners_105"),
            m("Under 10.5", o?.cornersUnder105, "corners_105"),
        ]
        groups.append(MarketGroup(title: "Corners", icon: "flag", markets: markets(cornerMarkets)))

        // 9. Cards
        let cardMarkets: [Market?] = [
            m("Over 1.5",  o?.cardsOver15,  "cards_15"),
            m("Under 1.5", o?.cardsUnder15, "cards_15"),
            m("Over 2.5",  o?.cardsOver25,  "cards_25"),
            m("Under 2.5", o?.cardsUnder25, "cards_25"),
            m("Over 3.5",  o?.cardsOver35,  "cards_35"),
            m("Under 3.5", o?.cardsUnder35, "cards_35"),
        ]
        groups.append(MarketGroup(title: "Cards", icon: "rectangle.portrait", markets: markets(cardMarkets)))

        // 10. Clean Sheet
        groups.append(MarketGroup(title: "Clean Sheet", icon: "lock.shield", markets: markets([
            m("\(match.home) Clean Sheet", o?.homeCleanSheet, "cs_home"),
            m("\(match.away) Clean Sheet", o?.awayCleanSheet, "cs_away"),
        ])))

        // 11. Player — Anytime Goalscorer
        let anyScorers = (o?.playerAnytime ?? []).compactMap {
            m($0.name, $0.odd, "player_anytime_\($0.name)")
        }
        groups.append(MarketGroup(title: "Anytime Goalscorer", icon: "person.fill.checkmark", markets: anyScorers))

        // 12. Player — First Goalscorer
        let firstScorers = (o?.playerFirstGoal ?? []).compactMap {
            m($0.name, $0.odd, "player_first_\($0.name)")
        }
        groups.append(MarketGroup(title: "First Goalscorer", icon: "1.circle.fill", markets: firstScorers))

        // 13. Player — Last Goalscorer
        let lastScorers = (o?.playerLastGoal ?? []).compactMap {
            m($0.name, $0.odd, "player_last_\($0.name)")
        }
        groups.append(MarketGroup(title: "Last Goalscorer", icon: "flag.checkered", markets: lastScorers))

        // 14. Player — To Be Carded
        let cardedPlayers = (o?.playerToBeCarded ?? []).compactMap {
            m($0.name, $0.odd, "player_card_\($0.name)")
        }
        groups.append(MarketGroup(title: "Player to Be Carded", icon: "rectangle.portrait.fill", markets: cardedPlayers))

        // 15. Player — To Assist
        let assists = (o?.playerToAssist ?? []).compactMap {
            m($0.name, $0.odd, "player_assist_\($0.name)")
        }
        groups.append(MarketGroup(title: "Player to Assist", icon: "hand.point.right.fill", markets: assists))

        // Filter out empty groups
        return groups.filter { !$0.isEmpty }
    }

    // MARK: - Combo Helpers

    var comboPoints: Int { selectedMarkets.reduce(0) { $0 + $1.pointsValue } }
    var isCombo: Bool { selectedMarkets.count > 1 }

    func toggle(_ market: Market) {
        if let idx = selectedMarkets.firstIndex(of: market) {
            selectedMarkets.remove(at: idx)
        } else {
            selectedMarkets.removeAll { $0.group == market.group }
            selectedMarkets.append(market)
        }
    }

    func isSelected(_ market: Market) -> Bool { selectedMarkets.contains(market) }
    func isConflicted(_ market: Market) -> Bool {
        selectedMarkets.contains { $0.group == market.group && $0 != market }
    }
    func clearSelections() { selectedMarkets = [] }

    // MARK: - Filtered Matches

    private func parseDate(_ raw: String) -> Date {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: raw) { return d }
        return Date()
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
        } catch let DecodingError.keyNotFound(key, _) {
            errorMessage = "Missing key: \(key.stringValue)"
        } catch let DecodingError.typeMismatch(type, _) {
            errorMessage = "Type mismatch: \(type)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refreshMatches() async { matchesLoaded = false; await loadMatches() }

    // MARK: - Submit

    func submitPicks(match: Match, myPicksCount: Int) async -> Bool {
        guard !selectedMarkets.isEmpty else { errorMessage = "Select at least one market"; return false }
        guard myPicksCount + selectedMarkets.count <= 5 else { errorMessage = "Max 5 picks per day"; return false }

        isSubmitting = true; errorMessage = nil
        let comboId = isCombo ? UUID().uuidString : nil

        do {
            for market in selectedMarkets {
                try await supabaseManager.createPick(
                    match: match.displayName,
                    market: market.label,
                    odds: market.odds,
                    probability: market.probability,
                    pointsPossible: market.pointsValue,
                    pointsLost: max(1, market.pointsValue / 2),
                    comboId: comboId
                )
            }
            clearSelections()
            isSubmitting = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
            return false
        }
    }
}
