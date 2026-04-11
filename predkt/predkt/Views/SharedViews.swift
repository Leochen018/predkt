import SwiftUI

// MARK: - TeamBadgeView
// ✅ Uses URLSession's shared URLCache (configured in APIManager)
// Images are cached to disk automatically — no repeated downloads
// AsyncImage with smooth fade-in transition

struct TeamBadgeView: View {
    let url: String?

    var body: some View {
        Group {
            if let urlStr = url, let imageURL = URL(string: urlStr) {
                CachedAsyncImage(url: imageURL)
            } else {
                placeholderBadge
            }
        }
    }

    private var placeholderBadge: some View {
        Circle()
            .fill(Color.predktCard)
            .overlay(
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.predktMuted)
            )
    }
}

// ✅ Custom image loader that uses URLCache properly
// AsyncImage doesn't use URLCache — this does
struct CachedAsyncImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var isLoading = false

    // Static cache shared across all instances
    private static let imageCache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else {
                Circle()
                    .fill(Color.predktCard)
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.predktMuted)
                    )
                    .onAppear { loadImage() }
            }
        }
    }

    private func loadImage() {
        guard !isLoading else { return }

        // 1. In-memory NSCache (instant)
        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            image = cached
            return
        }

        isLoading = true
        Task.detached(priority: .utility) {
            // 2. URL request with disk cache (URLSession auto-handles)
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let loaded = UIImage(data: data) {
                // Save to in-memory cache
                Self.imageCache.setObject(loaded, forKey: url as NSURL)
                await MainActor.run { image = loaded }
            }
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - MatchCardView (used in Feed)

struct MatchCardView: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TeamBadgeView(url: match.homeLogo).frame(width: 20, height: 20)
                Text(match.home).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if match.isLive || match.isFinished {
                Text(match.score).font(.system(size: 13, weight: .black)).foregroundStyle(.white)
            } else {
                Text(match.kickoffTime).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.predktLime)
            }

            HStack(spacing: 6) {
                Text(match.away).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).multilineTextAlignment(.trailing)
                TeamBadgeView(url: match.awayLogo).frame(width: 20, height: 20)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.predktCard).cornerRadius(10)
    }
}
