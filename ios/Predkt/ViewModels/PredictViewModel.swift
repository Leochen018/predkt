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
            print("🔄 Loading matches from API...")
            let rawMatches = try await APIManager.fetchLiveMatches()
            print("📊 Raw matches received: \(rawMatches.count)")

            // Convert raw dictionaries to Match objects
            var convertedMatches: [Match] = []
            for (index, dict) in rawMatches.enumerated() {
                print("🔍 Processing match \(index): \(dict)")

                if let fixtureId = dict["fixtureId"] as? Int,
                   let home = dict["home"] as? String,
                   let away = dict["away"] as? String,
                   let status = dict["status"] as? String,
                   let homeGoals = dict["homeGoals"] as? Int,
                   let awayGoals = dict["awayGoals"] as? Int,
                   let competition = dict["competition"] as? String,
                   let isLive = dict["isLive"] as? Bool,
                   let isFinished = dict["isFinished"] as? Bool {

                    let match = Match(
                        id: String(fixtureId),
                        home: home,
                        away: away,
                        status: status,
                        elapsed: dict["elapsed"] as? Int,
                        homeGoals: homeGoals,
                        awayGoals: awayGoals,
                        competition: competition,
                        isLive: isLive,
                        isFinished: isFinished
                    )
                    convertedMatches.append(match)
                } else {
                    print("⚠️ Could not parse match \(index): missing fields")
                }
            }

            if convertedMatches.isEmpty {
                print("⚠️ No valid matches found, using test data")
                self.matches = [
                    Match(id: "1", home: "Manchester United", away: "Liverpool", status: "LIVE", elapsed: 45, homeGoals: 1, awayGoals: 1, competition: "Premier League", isLive: true, isFinished: false),
                    Match(id: "2", home: "Chelsea", away: "Arsenal", status: "FT", elapsed: 90, homeGoals: 2, awayGoals: 2, competition: "Premier League", isLive: false, isFinished: true),
                ]
            } else {
                self.matches = convertedMatches
            }
            print("✅ Successfully loaded \(self.matches.count) matches")
        } catch {
            let errorMsg = "API Error: \(error.localizedDescription)"
            errorMessage = errorMsg
            print("❌ \(errorMsg)")

            // Use test data so you can at least see the UI
            self.matches = [
                Match(id: "1", home: "Test Home", away: "Test Away", status: "LIVE", elapsed: 45, homeGoals: 1, awayGoals: 0, competition: "Test League", isLive: true, isFinished: false),
            ]
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
