import Foundation
import Combine

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var confidence: Int = 70
    @Published var selectedMatch: Match?
    @Published var isSubmitting = false

    private let supabaseManager = SupabaseManager.shared
    
    // The definitive IDs for the Top 7 + European Cups
    private let topLeagueIDs = [
        39,   // Premier League (England)
        140,  // La Liga (Spain)
        135,  // Serie A (Italy)
        78,   // Bundesliga (Germany)
        61,   // Ligue 1 (France)
        94,   // Primeira Liga (Portugal)
        88,   // Eredivisie (Netherlands)
        2,    // Champions League
        3     // Europa League
    ]

    struct Market: Identifiable {
        let id = UUID()
        let label: String
        let odds: Double
        let category: String
    }

    var filteredMatches: [Match] {
        
        return matches.filter { match in
            // 1. Check League ID
            let isTopLeague = topLeagueIDs.contains(match.leagueId)
            
            // 2. Safe Date Comparison
            let calendar = Calendar.current
            let dateFormatter = ISO8601DateFormatter()
            // This handles the 'T' and timezone offsets in your API response
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let matchDate = dateFormatter.date(from: match.rawDate) ?? Date()
            let isSameDay = calendar.isDate(matchDate, inSameDayAs: selectedDate)
            
            return isTopLeague && isSameDay
        }
        .sorted { m1, m2 in
            if m1.isLive != m2.isLive {
                return m1.isLive && !m2.isLive
            }
            return m1.rawDate < m2.rawDate
        }
    }

    // MARK: - Updated Loading Logic
    func loadMatches() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch the full schedule from your updated APIManager
            // Ensure APIManager.fetchAllMatches() is implemented to get future games
            let allMatches = try await APIManager.fetchAllMatches()
            self.matches = allMatches
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ Missing Key: '\(key.stringValue)' - \(context.debugDescription)")
            errorMessage = "Data format error: Missing '\(key.stringValue)'"
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ Type Mismatch: expected '\(type)' - \(context.debugDescription)")
            errorMessage = "Data format error: Type mismatch"
        } catch {
            print("❌ General Error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getMarkets(for match: Match) -> [Market] {
        [
            Market(label: "Home Win", odds: 2.1, category: "match_result"),
            Market(label: "Away Win", odds: 1.9, category: "match_result"),
            Market(label: "Draw", odds: 3.2, category: "match_result"),
            Market(label: "Over 2.5 Goals", odds: 1.8, category: "goals"),
            Market(label: "Under 2.5 Goals", odds: 2.0, category: "goals"),
            Market(label: "Both Score", odds: 2.3, category: "both_score")
        ]
    }

    func submitPick(market: Market, match: Match, myPicksCount: Int) async -> Bool {
        guard myPicksCount < 5 else {
            errorMessage = "Max 5 picks per day"
            return false
        }

        isSubmitting = true
        errorMessage = nil

        let confRatio = Double(confidence) / 100.0
        let basePoints = Int(4.0 * market.odds * confRatio)
        let finalWin = max(1, basePoints)
        let finalLoss = max(1, Int(4.0 * market.odds * confRatio * 0.5))

        do {
            try await supabaseManager.createPick(
                match: match.displayName,
                market: market.label,
                confidence: confidence,
                odds: market.odds,
                difficulty: "easy",
                difficulty_multiplier: 1.0,
                points_possible: finalWin,
                points_lost: finalLoss
            )
            isSubmitting = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
            return false
        }
    }
}
