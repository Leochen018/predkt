import Foundation

// MARK: - Response Models

struct LiveResponse: Codable {
    let liveMatches: [LiveMatchResponse]
}

struct OddsResponse: Codable {
    let odds: MatchOdds?
}

// ✅ Keys match EXACTLY what the backend sends
struct LiveMatchResponse: Codable {
    let fixtureId:   Int
    let home:        String
    let away:        String
    let status:      String
    let elapsed:     Int?
    let homeGoals:   Int
    let awayGoals:   Int
    let competition: String
    let league_id:   Int?       // snake_case matches JSON key
    let date:        String     // ✅ non-optional — backend always sends this
    let homeLogo:    String?
    let awayLogo:    String?
    let venue:       String?
    let isLive:      Bool
    let isFinished:  Bool
    let odds:        MatchOdds? // null from new backend — that's fine

    func toMatch() -> Match {
        Match(
            id:          String(fixtureId),
            home:        home,
            away:        away,
            status:      status,
            elapsed:     elapsed,
            homeGoals:   homeGoals,
            awayGoals:   awayGoals,
            competition: competition,
            isLive:      isLive,
            isFinished:  isFinished,
            rawDate:     date,          // ✅ direct — no optional fallback
            leagueId:    league_id ?? 0,
            homeLogo:    homeLogo,
            awayLogo:    awayLogo,
            odds:        odds,
            venue:       venue
        )
    }
}

// MARK: - APIManager
// ✅ No @MainActor — all methods are nonisolated to avoid concurrency warnings
// Uses our own disk cache, not URLSession cache, to avoid stale response issues

final class APIManager {
    static let baseURL = "https://api.predkt.app"

    // URLSession with sensible timeout, no URL-level caching for match data
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy         = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

  

    // ── Disk cache ────────────────────────────────────────────────────────────
    private static let cacheFile: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("predkt_matches_v3.json")
    }()
    private static let cacheTTL: TimeInterval = 55 * 60 // 55 min

    // nonisolated(unsafe) — these are read/written only in controlled async contexts
    nonisolated(unsafe) private static var oddsMemCache: [String: MatchOdds?] = [:]

    private struct CacheWrapper: Codable {
        let matches: [Match]
        let savedAt: Date
    }

    private static func loadDiskCache() -> [Match]? {
        guard
            let data    = try? Data(contentsOf: cacheFile),
            let wrapper = try? JSONDecoder().decode(CacheWrapper.self, from: data),
            Date().timeIntervalSince(wrapper.savedAt) < cacheTTL,
            !wrapper.matches.isEmpty
        else { return nil }
        return wrapper.matches
    }

    private static func saveDiskCache(_ matches: [Match]) {
        guard !matches.isEmpty,
              let data = try? JSONEncoder().encode(CacheWrapper(matches: matches, savedAt: Date()))
        else { return }
        try? data.write(to: cacheFile, options: .atomic)
        print("💾 Disk cache saved: \(matches.count) matches")
    }

    // ── Fetch match list ──────────────────────────────────────────────────────
    // Stale-while-revalidate: return disk cache instantly, refresh in background

    static func fetchAllMatches() async throws -> [Match] {
        if let cached = loadDiskCache() {
            let days = Set(cached.map { String($0.rawDate.prefix(10)) })
            print("💾 Disk cache hit: \(cached.count) matches, \(days.count) days (\(days.sorted().first ?? "?") → \(days.sorted().last ?? "?"))")

            // Background refresh
            Task {
                if let fresh = try? await fetchFreshMatches() {
                    saveDiskCache(fresh)
                    await MainActor.run {
                        // ✅ Don't overwrite live match data with stale backend data
                        // The live poller handles live matches — only post non-live updates
                        NotificationCenter.default.post(name: .matchesRefreshed, object: fresh)
                    }
                }
            }
            return cached
        }
        // No cache — blocking fetch
        let matches = try await fetchFreshMatches()
        saveDiskCache(matches)
        return matches
    }

    static func fetchFreshMatches() async throws -> [Match] {
        guard let url = URL(string: "\(baseURL)/api/matches") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.cachePolicy         = .reloadIgnoringLocalCacheData
        request.timeoutInterval     = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        // Debug: print first 200 chars of response
        if let raw = String(data: data.prefix(200), encoding: .utf8) {
            print("📦 Raw response preview: \(raw)")
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LiveResponse.self, from: data)
        let matches = decoded.liveMatches.map { $0.toMatch() }

        let days = Set(matches.map { String($0.rawDate.prefix(10)) }).sorted()
        print("✅ Fetched \(matches.count) matches across \(days.count) days: \(days.first ?? "?") → \(days.last ?? "?")")

        if days.count <= 1 && matches.count > 20 {
            // Something is wrong — log a sample to debug
            print("⚠️ Only 1 day found! Sample rawDates:")
            decoded.liveMatches.prefix(3).forEach { m in
                print("   fixtureId=\(m.fixtureId) date=\(m.date) rawDate=\(m.toMatch().rawDate)")
            }
        }

        return matches
    }

    static func forceRefresh() async throws -> [Match] {
        let matches = try await fetchFreshMatches()
        saveDiskCache(matches)
        return matches
    }
    static func fetchLiveMatches() async throws -> [Match] {
        guard let url = URL(string: "\(baseURL)/api/live") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy     = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)
        let decoded   = try JSONDecoder().decode(LiveResponse.self, from: data)
        return decoded.liveMatches.map { $0.toMatch() }
    }

    // ── Lazy odds loading ─────────────────────────────────────────────────────

    static func fetchOdds(for match: Match) async -> MatchOdds? {
        let key = match.id
        if let cached = oddsMemCache[key] { return cached }
        if match.isLive || match.isFinished { return nil }

        guard let url = URL(string: "\(baseURL)/api/odds/\(match.id)") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await session.data(for: request)
            let decoded   = try JSONDecoder().decode(OddsResponse.self, from: data)
            oddsMemCache[key] = decoded.odds
            return decoded.odds
        } catch {
            print("⚠️ Odds error for \(match.displayName): \(error)")
            return nil
        }
    }

    static func prefetchOdds(for matches: [Match]) {
        let upcoming = matches.filter { !$0.isLive && !$0.isFinished && oddsMemCache[$0.id] == nil }
        guard !upcoming.isEmpty else { return }
        Task.detached(priority: .utility) {
            for match in upcoming {
                _ = await fetchOdds(for: match)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            print("🎰 Pre-fetched odds for \(upcoming.count) matches")
        }
    }
}

extension Notification.Name {
    static let matchesRefreshed = Notification.Name("predkt.matchesRefreshed")
}
