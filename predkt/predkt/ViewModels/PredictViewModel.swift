import Foundation
import Combine

@MainActor
final class PredictViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var confidence: Int = 70
    @Published var selectedMatch: Match?
    @Published var isSubmitting = false

    private let supabaseManager = SupabaseManager.shared

    // Market definition
    struct Market: Identifiable {
        let id = UUID()
        let label: String
        let odds: Double
        let category: String
    }

    func loadMatches() async {
        isLoading = true
        errorMessage = nil

        do {
            let liveMatches = try await APIManager.fetchLiveMatches()
            self.matches = liveMatches
        } catch let DecodingError.keyNotFound(key, context) {
            let msg = "❌ Missing Key: '\(key.stringValue)' - \(context.debugDescription)"
            print(msg)
            errorMessage = "Data format error: Missing '\(key.stringValue)'"
        } catch let DecodingError.typeMismatch(type, context) {
            let msg = "❌ Type Mismatch: expected '\(type)' - \(context.debugDescription)"
            print(msg)
            errorMessage = "Data format error: Type mismatch"
        } catch let DecodingError.valueNotFound(type, context) {
            let msg = "❌ Value Not Found: expected '\(type)' but found null - \(context.debugDescription)"
            print(msg)
            errorMessage = "Data format error: Missing value"
        } catch let DecodingError.dataCorrupted(context) {
            let msg = "❌ Data Corrupted: \(context.debugDescription)"
            print(msg)
            errorMessage = "Data format error: Corrupted data"
        } catch {
            print("❌ General Error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getMarkets(for match: Match) -> [Market] {
        // Hardcoded markets for demo; in production, fetch from Supabase
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

        // Calculate points (mirrored from web app)
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
