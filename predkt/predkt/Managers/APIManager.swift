import Foundation

struct LiveResponse: Codable {
    let liveMatches: [LiveMatchResponse]
}

struct OddsResponse: Codable {
    let odds: MatchOdds?
}

final class APIManager {
    static let baseURL = "https://api.predkt.app"

    // ── URLSession configured for performance ────────────────────────────────
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        // ✅ Large URL cache — 50MB memory, 200MB disk
        // This caches HTTP responses automatically including team badge images
        config.urlCache = URLCache(
            memoryCapacity:   50  * 1024 * 1024,
            diskCapacity:    200  * 1024 * 1024
        )
        config.requestCachePolicy  = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    // ── Disk cache for match list ────────────────────────────────────────────
    private static let cacheFile: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("predkt_matches_v2.json")
    }()
    private static let cacheTTL: TimeInterval = 55 * 60 // 55 min (slightly under server's 60)

    private static func loadDiskCache() -> [Match]? {
        guard let data    = try? Data(contentsOf: cacheFile),
              let wrapper = try? JSONDecoder().decode(CacheWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < cacheTTL
        else { return nil }
        return wrapper.matches
    }

    private static func saveDiskCache(_ matches: [Match]) {
        guard let data = try? JSONEncoder().encode(CacheWrapper(matches: matches, savedAt: Date()))
        else { return }
        try? data.write(to: cacheFile, options: .atomic)
    }

    private struct CacheWrapper: Codable {
        let matches: [Match]
        let savedAt: Date
    }

    // ── Odds memory cache ────────────────────────────────────────────────────
    // Keeps odds in memory so tapping the same match twice is instant
    private static var oddsMemCache: [String: MatchOdds?] = [:]

    // ── Fetch match list (stale-while-revalidate) ────────────────────────────
    // Returns disk cache immediately, then fetches fresh in background.
    // ViewModel gets two rapid updates: instant cached, then fresh data.

    static func fetchAllMatches() async throws -> [Match] {
        if let cached = loadDiskCache() {
            // Return cache immediately, refresh in background
            Task.detached(priority: .utility) {
                if let fresh = try? await fetchFreshMatches() {
                    saveDiskCache(fresh)
                    // Notify via NotificationCenter so ViewModel can update
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .matchesRefreshed,
                            object: fresh
                        )
                    }
                }
            }
            return cached
        }
        // No cache — fetch fresh (first launch or cache expired)
        let matches = try await fetchFreshMatches()
        saveDiskCache(matches)
        return matches
    }

    private static func fetchFreshMatches() async throws -> [Match] {
        guard let url = URL(string: "\(baseURL)/api/matches") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData // always fresh from server
        let (data, _) = try await session.data(for: request)
        let decoded   = try JSONDecoder().decode(LiveResponse.self, from: data)
        let matches   = decoded.liveMatches.map { $0.toMatch() }
        let days      = Set(matches.map { String($0.rawDate.prefix(10)) })
        print("✅ Fetched \(matches.count) matches across \(days.count) days")
        return matches
    }

    static func forceRefresh() async throws -> [Match] {
        let matches = try await fetchFreshMatches()
        saveDiskCache(matches)
        return matches
    }

    // ── Fetch odds lazily for one match ──────────────────────────────────────
    // Called only when user taps a match — avoids bulk odds fetching on load

    static func fetchOdds(for match: Match) async -> MatchOdds? {
        let key = match.id

        // 1. Memory cache
        if let cached = oddsMemCache[key] { return cached }

        // 2. Match already started — no odds
        if match.isLive || match.isFinished { return nil }

        // 3. Fetch from server
        guard let url = URL(string: "\(baseURL)/api/odds/\(match.id)") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await session.data(for: request)
            let decoded   = try JSONDecoder().decode(OddsResponse.self, from: data)
            oddsMemCache[key] = decoded.odds // cache in memory
            return decoded.odds
        } catch {
            print("⚠️ Odds fetch failed for \(match.displayName): \(error)")
            return nil
        }
    }

    // Pre-fetch odds for all matches on a specific date (called when user swipes to a day)
    static func prefetchOdds(for matches: [Match]) {
        let upcoming = matches.filter { !$0.isLive && !$0.isFinished }
        guard !upcoming.isEmpty else { return }
        Task.detached(priority: .utility) {
            for match in upcoming {
                guard oddsMemCache[match.id] == nil else { continue }
                _ = await fetchOdds(for: match)
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between requests
            }
        }
    }
}

extension Notification.Name {
    static let matchesRefreshed = Notification.Name("matchesRefreshed")
}
