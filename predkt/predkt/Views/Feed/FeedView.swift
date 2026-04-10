import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedTab = 0
    let tabs = ["For You", "Following", "Live"]

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    Text("predkt")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                    Spacer()
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.white)
                            .font(.system(size: 17))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))

                // MARK: Tab Bar
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                        Button(action: { withAnimation { selectedTab = i } }) {
                            VStack(spacing: 6) {
                                HStack(spacing: 5) {
                                    if tab == "Live" {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(tab)
                                        .font(.system(size: 14, weight: selectedTab == i ? .bold : .medium))
                                        .foregroundStyle(selectedTab == i ? .white : .gray)
                                }
                                Rectangle()
                                    .fill(selectedTab == i
                                          ? Color(red: 0.42, green: 0.39, blue: 1.0)
                                          : .clear)
                                    .frame(height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))

                // MARK: Content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.42, green: 0.39, blue: 1.0)))
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        ForYouTab(viewModel: viewModel).tag(0)
                        FollowingTab(viewModel: viewModel).tag(1)
                        LiveTab(viewModel: viewModel).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $viewModel.showInterestsPicker) {
            InterestsPickerView(viewModel: viewModel)
        }
    }
}

// MARK: - For You Tab

struct ForYouTab: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // Interests prompt if none set
                if viewModel.followedLeagueIds.isEmpty && viewModel.followedTeamNames.isEmpty {
                    InterestsPromptCard(onTap: { viewModel.showInterestsPicker = true })
                }

                // Suggested matches based on interests
                if !viewModel.suggestedMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("SUGGESTED MATCHES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                            Spacer()
                            Text("Based on your interests")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                        }

                        ForEach(viewModel.suggestedMatches.prefix(5)) { match in
                            SuggestedMatchCard(match: match)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Divider
                if !viewModel.suggestedMatches.isEmpty && !viewModel.feedPicks.isEmpty {
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        Text("COMMUNITY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 8)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                }

                // Community picks
                ForEach(viewModel.feedPicks) { pick in
                    PickCard(pick: pick)
                        .padding(.horizontal, 16)
                }

                if viewModel.feedPicks.isEmpty && viewModel.suggestedMatches.isEmpty {
                    EmptyFeedCard()
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Following Tab

struct FollowingTab: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Followed leagues matches
                if !viewModel.followedLeagueIds.isEmpty || !viewModel.followedTeamNames.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR LEAGUES & TEAMS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                            .padding(.horizontal, 16)

                        ForEach(viewModel.suggestedMatches) { match in
                            SuggestedMatchCard(match: match)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.gray.opacity(0.3))
                        Text("Follow teams and leagues to see their matches here")
                            .font(.system(size: 14))
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                        Button(action: { viewModel.showInterestsPicker = true }) {
                            Text("Choose Interests")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                                .cornerRadius(20)
                        }
                    }
                    .padding(.top, 100)
                    .padding(.horizontal, 40)
                }

                Spacer().frame(height: 80)
            }
        }
    }
}

// MARK: - Live Tab

struct LiveTab: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.liveMatches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 36))
                            .foregroundStyle(.gray.opacity(0.3))
                        Text("No matches live right now")
                            .font(.system(size: 14))
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 100)
                } else {
                    ForEach(viewModel.liveMatches) { match in
                        LiveMatchCard(match: match)
                            .padding(.horizontal, 16)
                    }
                }
                Spacer().frame(height: 80)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Suggested Match Card

struct SuggestedMatchCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 0) {
            // League bar
            HStack(spacing: 6) {
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("• \(match.kickoffTime)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                }
                Text(match.competition.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Teams
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if match.isLive || match.isFinished {
                    Text(match.score)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60)
                } else {
                    Text("VS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.gray)
                        .frame(width: 60)
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
                .stroke(match.isLive ? Color.red.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Live Match Card

struct LiveMatchCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                }
                Text("·")
                    .foregroundStyle(.gray)
                Text(match.competition)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Spacer()
            }

            HStack {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(match.score)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 10) {
                    Text(match.away)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    TeamBadgeView(url: match.awayLogo)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Pick Card

struct PickCard: View {
    let pick: Pick

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String((pick.profiles?.username ?? pick.username ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.profiles?.username ?? pick.username ?? "Anonymous")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(pick.match)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                Spacer()
                Text(pick.resultIcon)
                    .font(.system(size: 16))
            }

            HStack(spacing: 8) {
                Text(pick.market)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.3), lineWidth: 1)
                    )

                Text("\(pick.confidence)% confidence")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)

                Spacer()

                Text(String(format: "%.2f", pick.odds))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
            }
        }
        .padding(14)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(12)
    }
}

// MARK: - Interests Prompt Card

struct InterestsPromptCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalise your feed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Follow your favourite teams & leagues")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.gray)
                    .font(.system(size: 13))
            }
            .padding(16)
            .background(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty Feed

struct EmptyFeedCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 36))
                .foregroundStyle(.gray.opacity(0.3))
            Text("No picks yet today")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
        }
        .padding(.top, 80)
    }
}
