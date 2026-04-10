import SwiftUI

// MARK: - Team Badge
// Used in PredictView, FeedView, and MarketSheetView

struct TeamBadgeView: View {
    let url: String?

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        badgePlaceholder
                    }
                }
            } else {
                badgePlaceholder
            }
        }
        .frame(width: 28, height: 28)
    }

    private var badgePlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 28, height: 28)
    }
}

// MARK: - Match Card
// Used in PredictView match list

struct MatchCardView: View {
    let match: Match

    var body: some View {
        VStack(spacing: 0) {
            // League / status bar
            HStack(spacing: 6) {
                Text(match.competition)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text(match.elapsed.map { "\($0)'" } ?? "LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Teams row
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Centre: score or kickoff time
                if match.isLive || match.isFinished {
                    Text(match.score)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64)
                } else {
                    VStack(spacing: 1) {
                        Text(match.kickoffTime)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                        Text("KO")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.7))
                    }
                    .frame(width: 64)
                }

                HStack(spacing: 10) {
                    Text(match.away)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                    TeamBadgeView(url: match.awayLogo)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    match.isLive ? Color.red.opacity(0.3) : Color.white.opacity(0.05),
                    lineWidth: 1
                )
        )
    }
}
