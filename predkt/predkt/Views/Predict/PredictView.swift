import SwiftUI

struct PredictView: View {
    @StateObject private var viewModel = PredictViewModel()
    @State private var showingMarketSheet = false
    @State private var selectedMatch: Match?
    @State private var myPicksCount = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Text("Predict")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(16)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))

                // MARK: - Horizontal Calendar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<14) { i in
                            let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) ?? Date()
                            DateItemView(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
                            ) {
                                viewModel.selectedDate = date
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))

                // MARK: - Match List
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
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(20)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(viewModel.filteredMatches, id: \.id) { match in
                                Button(action: {
                                    selectedMatch = match
                                    showingMarketSheet = true
                                }) {
                                    MatchCardView(match: match)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if viewModel.filteredMatches.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "sportscourt")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.gray.opacity(0.3))
                                    Text("No matches scheduled for the Top 7 Leagues today.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 100)
                                .padding(.horizontal, 40)
                            }

                            Spacer().frame(height: 20)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadMatches() }
        }
        .sheet(isPresented: $showingMarketSheet) {
            if let match = selectedMatch {
                MarketSheetView(
                    match: match,
                    viewModel: viewModel,
                    myPicksCount: myPicksCount,
                    isPresented: $showingMarketSheet
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Match Card

struct MatchCardView: View {
    let match: Match

    var body: some View {
        VStack(spacing: 0) {
            // Competition bar
            HStack(spacing: 6) {
                Text(match.competition)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 5, height: 5)
                        Text(match.elapsed.map { "\($0)'" } ?? "LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Teams row
            HStack(spacing: 0) {
                // Home team
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Score / Time / VS
                VStack(spacing: 2) {
                    if match.isLive || match.isFinished {
                        Text(match.score)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(match.kickoffTime)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                        Text("KO")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.7))
                    }
                }
                .frame(width: 64)

                // Away team
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
                    match.isLive
                        ? Color.red.opacity(0.3)
                        : Color.white.opacity(0.05),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Team Badge

struct TeamBadgeView: View {
    let url: String?

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure, .empty:
                        badgePlaceholder
                    @unknown default:
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

// MARK: - Date Item

struct DateItemView: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(isSelected ? .white : .gray)
            .frame(width: 50, height: 65)
            .background(isSelected
                ? Color(red: 0.42, green: 0.39, blue: 1.0)
                : Color(red: 0.15, green: 0.15, blue: 0.18))
            .cornerRadius(12)
        }
    }
}

// MARK: - Market Sheet

struct MarketSheetView: View {
    let match: Match
    let viewModel: PredictViewModel
    let myPicksCount: Int
    @Binding var isPresented: Bool
    @State private var selectedMarket: PredictViewModel.Market?

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()
            VStack(spacing: 16) {
                // Match header with badges
                HStack(spacing: 12) {
                    TeamBadgeView(url: match.homeLogo)
                    VStack(spacing: 2) {
                        Text(match.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        if match.isLive {
                            Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.red)
                        } else if !match.isFinished {
                            Text("KO \(match.kickoffTime)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                        }
                    }
                    TeamBadgeView(url: match.awayLogo)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                            .font(.title3)
                    }
                }
                .padding(16)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.getMarkets(for: match)) { market in
                            Button(action: { selectedMarket = market }) {
                                HStack {
                                    Text(market.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(String(format: "%.2f", market.odds))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                }
                                .padding(14)
                                .background(selectedMarket?.id == market.id
                                    ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15)
                                    : Color(red: 0.1, green: 0.1, blue: 0.12))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedMarket?.id == market.id
                                            ? Color(red: 0.42, green: 0.39, blue: 1.0)
                                            : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if let market = selectedMarket {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Confidence")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.gray)
                            Spacer()
                            Text("\(viewModel.confidence)%")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.confidence) },
                                set: { viewModel.confidence = Int($0) }
                            ),
                            in: 1...100
                        )
                        .tint(Color(red: 0.42, green: 0.39, blue: 1.0))

                        Button(action: {
                            Task {
                                let success = await viewModel.submitPick(
                                    market: market,
                                    match: match,
                                    myPicksCount: myPicksCount
                                )
                                if success { isPresented = false }
                            }
                        }) {
                            Group {
                                if viewModel.isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Submit Pick")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isSubmitting)
                    }
                    .padding(20)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
        }
    }
}
