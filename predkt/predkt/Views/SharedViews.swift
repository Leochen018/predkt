import SwiftUI

// MARK: - TeamBadgeView
// Uses APIManager.imageSession which has a large URLCache for disk-persisted images
// Images are downloaded once and cached to disk — no repeated network calls

struct TeamBadgeView: View {
    let url: String?

    var body: some View {
        if let urlStr = url, let imageURL = URL(string: urlStr) {
            CachedAsyncImage(url: imageURL)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Circle()
            .fill(Color.predktCard)
            .overlay(
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.predktMuted)
            )
    }
}

// MARK: - CachedAsyncImage
// ✅ No actor issues — uses a simple actor for the in-memory image cache

actor ImageCacheActor {
    static let shared = ImageCacheActor()
    private var cache: [URL: UIImage] = [:]

    func get(_ url: URL) -> UIImage? { cache[url] }
    func set(_ image: UIImage, for url: URL) { cache[url] = image }
}

struct CachedAsyncImage: View {
    let url: URL
    @State private var image:     UIImage? = nil
    @State private var isLoading: Bool     = false

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else {
                Circle()
                    .fill(Color.predktCard)
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.predktMuted)
                    )
            }
        }
        .onAppear {
            guard image == nil, !isLoading else { return }
            isLoading = true
            Task {
                // 1. Check actor cache (in-memory, instant)
                if let cached = await ImageCacheActor.shared.get(url) {
                    await MainActor.run { image = cached; isLoading = false }
                    return
                }
                // 2. Fetch via session with disk cache
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                if let (data, _) = try? await APIManager.imageSession.data(for: request),
                   let loaded = UIImage(data: data) {
                    await ImageCacheActor.shared.set(loaded, for: url)
                    await MainActor.run { image = loaded }
                }
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// MARK: - MatchCardView

struct MatchCardView: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TeamBadgeView(url: match.homeLogo).frame(width: 20, height: 20)
                Text(match.home)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if match.isLive || match.isFinished {
                Text(match.score)
                    .font(.system(size: 13, weight: .black)).foregroundStyle(.white)
            } else {
                Text(match.kickoffTime)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.predktLime)
            }

            HStack(spacing: 6) {
                Text(match.away)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1).multilineTextAlignment(.trailing)
                TeamBadgeView(url: match.awayLogo).frame(width: 20, height: 20)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.predktCard).cornerRadius(10)
    }
}
