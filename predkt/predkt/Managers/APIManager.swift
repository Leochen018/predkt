import Foundation

struct LiveResponse: Codable {
    let liveMatches: [LiveMatchResponse]
}

final class APIManager {
    static let baseURL = "https://api.predkt.app"

    // ── Local disk cache ──────────────────────────────────────────────────────
    // Stores the last successful response to disk.
    // On next launch the app shows cached data instantly while refreshing in background.

    private static let cacheFile: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("matches_cache.json")
    }()

    private static let cacheTTL: TimeInterval = 60 * 60 // 1 hour

    private static func loadDiskCache() -> [Match]? {
        guard let data = try? Data(contentsOf: cacheFile),
              let wrapper = try? JSONDecoder().decode(CacheWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < cacheTTL
        else { return nil }
        return wrapper.matches
    }

    private static func saveDiskCache(_ matches: [Match]) {
        let wrapper = CacheWrapper(matches: matches, savedAt: Date())
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    private struct CacheWrapper: Codable {
        let matches: [Match]
        let savedAt: Date
    }

    // ── Fetch with stale-while-revalidate ────────────────────────────────────
    // Returns cached data immediately, then fetches fresh in background.
    // ViewModel gets two updates: instant cached, then fresh.

    static func fetchAllMatches() async throws -> [Match] {
        // 1. Try disk cache first for instant display
        if let cached = loadDiskCache() {
            // Return cached now, refresh in background
            Task.detached(priority: .background) {
                _ = try? await fetchFresh()
            }
            return cached
        }
        // 2. No cache — fetch fresh (first launch)
        return try await fetchFresh()
    }

    @discardableResult
    static func fetchFresh() async throws -> [Match] {
        guard let url = URL(string: "\(baseURL)/api/matches") else {
            throw URLError(.badURL)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 90   // Railway cold start can take 60s
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        // Log raw response size for debugging
        print("📦 Response: \(data.count / 1024)KB")

        let decoded  = try JSONDecoder().decode(LiveResponse.self, from: data)
        let matches  = decoded.liveMatches.map { $0.toMatch() }

        // Log date spread
        let dates = Set(matches.map { String($0.rawDate.prefix(10)) }).sorted()
        print("✅ Fetched \(matches.count) matches across \(dates.count) days: \(dates.first ?? "?") → \(dates.last ?? "?")")

        // Save to disk cache
        saveDiskCache(matches)
        return matches
    }

    // Force refresh — ignores disk cache
    static func forceRefresh() async throws -> [Match] {
        return try await fetchFresh()
    }
}
