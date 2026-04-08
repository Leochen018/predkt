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
                // Header
                HStack {
                    Text("Predict")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
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
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(20)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.matches) { match in
                                Button(action: {
                                    selectedMatch = match
                                    showingMarketSheet = true
                                }) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(match.displayName)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text(match.competition)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                                        }
                                        Spacer()
                                        
                                        if match.isLive {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(.red)
                                                    .frame(width: 6, height: 6)
                                                Text("LIVE")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.red)
                                            }
                                        } else if match.isFinished {
                                            Text(match.score)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.74, green: 0.72, blue: 0.85))
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                                    .cornerRadius(10)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(PlainButtonStyle()) // Keeps text colors intact
                            }
                            Spacer().frame(height: 20)
                        }
                        .padding(.vertical, 12)
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
                .presentationDetents([.medium, .large]) // Allows for a better half-sheet feel
            }
        }
    }
}

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
                // Header
                HStack {
                    Text(match.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                            .font(.title3)
                    }
                }
                .padding(16)

                // Markets List
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
                                .background(selectedMarket?.id == market.id ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15) : Color(red: 0.1, green: 0.1, blue: 0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedMarket?.id == market.id ? Color(red: 0.42, green: 0.39, blue: 1.0) : .clear, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Interaction Area (Slider & Submit)
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

                        Slider(value: Binding(
                            get: { Double(viewModel.confidence) },
                            set: { viewModel.confidence = Int($0) }
                        ), in: 1...100)
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

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                
                Spacer()
            }
        }
    }
}

#Preview {
    PredictView()
}
