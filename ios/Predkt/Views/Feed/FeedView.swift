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
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        Task { await viewModel.refresh() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.gray)
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
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(20)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Today's Picks
                            if !viewModel.myPicks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Today's Picks")
                                        .font(.system(size: 14, weight: .600))
                                        .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))
                                        .padding(.horizontal, 16)

                                    ForEach(viewModel.myPicks) { pick in
                                        PickCardView(pick: pick)
                                    }
                                }
                                .padding(.top, 12)

                                Divider()
                                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                                    .padding(.vertical, 12)
                            }

                            // Community Feed
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Community Feed")
                                    .font(.system(size: 14, weight: .600))
                                    .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))
                                    .padding(.horizontal, 16)

                                ForEach(viewModel.feedPicks) { pick in
                                    PickCardView(pick: pick)
                                }
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
}

struct PickCardView: View {
    let pick: Pick

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pick.market)
                        .font(.system(size: 14, weight: .600))
                        .foregroundColor(.white)
                    Text(pick.match)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.6, green: 0.59, blue: 0.68))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(pick.resultIcon)
                        Text(pick.result.uppercased())
                            .font(.system(size: 10, weight: .600))
                    }
                    .foregroundColor(Color(UIColor(red: CGFloat(Int(pick.resultColor.dropFirst(), radix: 16)!) >> 16 / 255.0, green: CGFloat((Int(pick.resultColor.dropFirst(), radix: 16)!) >> 8 & 0xFF) / 255.0, blue: CGFloat(Int(pick.resultColor.dropFirst(), radix: 16)! & 0xFF) / 255.0, alpha: 1.0)))
                    .padding(4)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                    .cornerRadius(4)
                }
            }

            HStack(spacing: 12) {
                Label("\(pick.confidence)%", systemImage: "target")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))

                if let odds = String(format: "%.2f", pick.odds) as String? {
                    Label(odds, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))
                }

                Spacer()

                if let username = pick.username {
                    Text(username)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
}

#Preview {
    FeedView()
}
