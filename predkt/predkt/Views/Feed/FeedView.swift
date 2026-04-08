import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Feed")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: {
                        Task { await viewModel.refresh() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.gray)
                    }
                }
                .padding(16)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))

                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.42, green: 0.39, blue: 1.0)))
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if !viewModel.myPicks.isEmpty {
                                sectionHeader("Today's Picks")
                                ForEach(viewModel.myPicks) { pick in
                                    PickCardView(pick: pick)
                                }
                                Divider()
                                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                                    .padding(.vertical, 12)
                            }

                            sectionHeader("Community Feed")
                            ForEach(viewModel.feedPicks) { pick in
                                PickCardView(pick: pick)
                            }

                            Spacer().frame(height: 20)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.74, green: 0.72, blue: 0.85))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PickCardView: View {
    let pick: Pick

    private var statusColor: Color {
        let hex = pick.resultColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pick.market)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(pick.match)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(pick.resultIcon)
                    Text(pick.result.uppercased())
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(statusColor)
                .padding(4)
                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                .cornerRadius(4)
            }

            HStack(spacing: 12) {
                Label("\(pick.confidence)%", systemImage: "target")
                Label(String(format: "%.2f", pick.odds), systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                if let username = pick.username {
                    Text(username)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.74, green: 0.72, blue: 0.85))
        }
        .padding(12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
}
