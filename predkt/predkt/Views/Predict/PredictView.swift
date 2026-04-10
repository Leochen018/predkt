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
                HStack {
                    Text("Predict")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                }
                .padding(16)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<14) { i in
                            let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) ?? Date()
                            DateItemView(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
                            ) { viewModel.selectedDate = date }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 12)
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.42, green: 0.39, blue: 1.0)))
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    Text(error).foregroundStyle(.red).padding(20)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(viewModel.filteredMatches, id: \.id) { match in
                                Button(action: {
                                    viewModel.clearSelections()
                                    selectedMatch = match
                                    showingMarketSheet = true
                                }) {
                                    MatchCardView(match: match)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if viewModel.filteredMatches.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "sportscourt").font(.system(size: 40)).foregroundStyle(.gray.opacity(0.3))
                                    Text("No matches scheduled for the Top 7 Leagues today.")
                                        .font(.system(size: 13)).foregroundStyle(.gray).multilineTextAlignment(.center)
                                }
                                .padding(.top, 100).padding(.horizontal, 40)
                            }
                            Spacer().frame(height: 20)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear { Task { await viewModel.loadMatches() } }
        .sheet(isPresented: $showingMarketSheet) {
            if let match = selectedMatch {
                MarketSheetView(match: match, viewModel: viewModel, myPicksCount: myPicksCount, isPresented: $showingMarketSheet)
            }
        }
    }
}

// MARK: - Market Sheet

struct MarketSheetView: View {
    let match: Match
    @ObservedObject var viewModel: PredictViewModel
    let myPicksCount: Int
    @Binding var isPresented: Bool

    var marketGroups: [PredictViewModel.MarketGroup] {
        viewModel.getMarketGroups(for: match)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Match header
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        TeamBadgeView(url: match.homeLogo)
                        VStack(spacing: 2) {
                            Text(match.displayName)
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            if match.isLive {
                                Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                            } else if !match.isFinished {
                                Text("KO \(match.kickoffTime)")
                                    .font(.system(size: 10)).foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                            }
                        }
                        TeamBadgeView(url: match.awayLogo)
                        Spacer()
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.gray).font(.title3)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 16)

                    if !viewModel.selectedMarkets.isEmpty {
                        ComboBetslipBar(viewModel: viewModel).padding(.horizontal, 16)
                    }
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                .padding(.bottom, 4)

                // All market groups
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(marketGroups) { group in
                            MarketGroupSection(group: group, viewModel: viewModel)
                        }

                        if viewModel.isCombo {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                Text("All legs must win for a combo to pay out")
                                    .font(.system(size: 11)).foregroundStyle(.gray)
                            }
                            .padding(10)
                            .background(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        Spacer().frame(height: viewModel.selectedMarkets.isEmpty ? 40 : 100)
                    }
                }
            }

            // Floating submit button
            if !viewModel.selectedMarkets.isEmpty {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.05, blue: 0.08).opacity(0), Color(red: 0.05, green: 0.05, blue: 0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 20)

                    Button(action: {
                        Task {
                            let success = await viewModel.submitPicks(match: match, myPicksCount: myPicksCount)
                            if success { isPresented = false }
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.isCombo ? "\(viewModel.selectedMarkets.count)-Leg Combo" : "Submit Pick")
                                    .font(.system(size: 15, weight: .bold))
                                Text(viewModel.selectedMarkets.map { $0.label }.joined(separator: " + "))
                                    .font(.system(size: 10)).opacity(0.75).lineLimit(1)
                            }
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("+\(viewModel.comboPoints) pts")
                                    .font(.system(size: 18, weight: .black))
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 60)
                        .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                        .foregroundStyle(.white)
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Market Group Section

struct MarketGroupSection: View {
    let group: PredictViewModel.MarketGroup
    @ObservedObject var viewModel: PredictViewModel
    @State private var isExpanded = true

    // Player prop groups use a list layout, others use a grid
    var isPlayerGroup: Bool {
        group.markets.first?.group.hasPrefix("player_") ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: group.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                        .frame(width: 20)
                    Text(group.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                if isPlayerGroup {
                    // List layout for player props
                    VStack(spacing: 6) {
                        ForEach(group.markets) { market in
                            PlayerMarketRow(market: market, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    // Grid layout for standard markets
                    LazyVGrid(
                        columns: group.markets.count == 2
                            ? [GridItem(.flexible()), GridItem(.flexible())]
                            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(group.markets) { market in
                            MarketButton(market: market, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Standard Market Button

struct MarketButton: View {
    let market: PredictViewModel.Market
    @ObservedObject var viewModel: PredictViewModel

    var isSelected: Bool    { viewModel.isSelected(market) }
    var isConflicted: Bool  { viewModel.isConflicted(market) }

    var riskColour: Color {
        switch market.probability {
        case 0..<30: return Color(red: 0.94, green: 0.31, blue: 0.31)
        case 30..<55: return Color(red: 0.95, green: 0.65, blue: 0.18)
        default:     return Color(red: 0.24, green: 0.78, blue: 0.47)
        }
    }

    var body: some View {
        Button(action: { viewModel.toggle(market) }) {
            VStack(spacing: 5) {
                Text(market.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isConflicted ? .gray.opacity(0.4) : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(market.probabilityDisplay)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(isSelected ? .white : riskColour)
                Text("+\(market.pointsValue)pts")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 4)
            .background(isSelected ? Color(red: 0.42, green: 0.39, blue: 1.0) : Color(red: 0.12, green: 0.12, blue: 0.15))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(red: 0.42, green: 0.39, blue: 1.0) : Color.white.opacity(0.06), lineWidth: 1))
            .opacity(isConflicted ? 0.35 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicted)
    }
}

// MARK: - Player Market Row (list style)

struct PlayerMarketRow: View {
    let market: PredictViewModel.Market
    @ObservedObject var viewModel: PredictViewModel

    var isSelected: Bool { viewModel.isSelected(market) }

    var body: some View {
        Button(action: { viewModel.toggle(market) }) {
            HStack(spacing: 12) {
                // Player avatar placeholder
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(market.label.prefix(1)))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.gray)
                    )

                Text(market.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(market.probabilityDisplay)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Color(red: 0.42, green: 0.39, blue: 1.0))
                    Text("+\(market.pointsValue)pts")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .gray)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(isSelected ? Color(red: 0.42, green: 0.39, blue: 1.0) : Color(red: 0.12, green: 0.12, blue: 0.15))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(red: 0.42, green: 0.39, blue: 1.0) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Combo Betslip Bar

struct ComboBetslipBar: View {
    @ObservedObject var viewModel: PredictViewModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isCombo ? "\(viewModel.selectedMarkets.count)-LEG COMBO" : "SINGLE PICK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(viewModel.selectedMarkets) { market in
                            Text(market.label)
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.white.opacity(0.08)).cornerRadius(4)
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("POTENTIAL").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
                Text("+\(viewModel.comboPoints) pts")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
            }
        }
        .padding(12)
        .background(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.1))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.3), lineWidth: 1))
        .padding(.bottom, 8)
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
            .background(isSelected ? Color(red: 0.42, green: 0.39, blue: 1.0) : Color(red: 0.15, green: 0.15, blue: 0.18))
            .cornerRadius(12)
        }
    }
}
