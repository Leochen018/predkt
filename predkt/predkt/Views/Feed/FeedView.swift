import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedTab = 0
    let tabs = ["For You", "Following", "🔴 Live"]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARENA")
                            .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Community plays")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.predktLime)
                            .font(.system(size: 16))
                            .padding(10)
                            .background(Color.predktLime.opacity(0.12))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                // Tabs
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                        Button(action: { withAnimation { selectedTab = i } }) {
                            VStack(spacing: 6) {
                                Text(tab)
                                    .font(.system(size: 13, weight: selectedTab == i ? .bold : .medium))
                                    .foregroundStyle(selectedTab == i ? .white : Color.predktMuted)
                                Rectangle()
                                    .fill(selectedTab == i ? Color.predktLime : .clear)
                                    .frame(height: 2).cornerRadius(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.predktCard.opacity(0.6))

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.predktLime))
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        ForYouFeed(viewModel: viewModel).tag(0)
                        FollowingFeed(viewModel: viewModel).tag(1)
                        LiveFeed(viewModel: viewModel).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .onAppear { Task { await viewModel.load() } }
        .sheet(isPresented: $viewModel.showInterestsPicker) {
            InterestsPickerView(viewModel: viewModel)
        }
    }
}

// MARK: - For You Feed

struct ForYouFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Interests prompt
                if viewModel.followedLeagueIds.isEmpty && viewModel.followedTeamNames.isEmpty {
                    ArenaInterestsPrompt(onTap: { viewModel.showInterestsPicker = true })
                }

                // Suggested matches section
                if !viewModel.suggestedMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("🎯 CHALLENGES FOR YOU")
                                .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktLime).kerning(1.5)
                            Spacer()
                        }
                        ForEach(viewModel.suggestedMatches.prefix(4)) { match in
                            ArenaMatchCard(match: match)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Divider
                if !viewModel.feedPicks.isEmpty {
                    HStack {
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                        Text("COMMUNITY PLAYS")
                            .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktMuted).kerning(2)
                            .fixedSize()
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                }

                // Community picks
                ForEach(viewModel.feedPicks) { pick in
                    ArenaPickCard(pick: pick)
                        .padding(.horizontal, 16)
                }

                if viewModel.feedPicks.isEmpty && viewModel.suggestedMatches.isEmpty {
                    ArenaEmptyState()
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Following Feed

struct FollowingFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.suggestedMatches.isEmpty && viewModel.followedLeagueIds.isEmpty {
                    VStack(spacing: 16) {
                        Text("❤️").font(.system(size: 44))
                        Text("Nothing here yet").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                        Text("Follow teams and leagues to see their challenges here")
                            .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                        Button(action: { viewModel.showInterestsPicker = true }) {
                            Text("Choose Interests")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.predktLime).cornerRadius(20)
                        }
                    }
                    .padding(.top, 100).padding(.horizontal, 40)
                } else {
                    HStack {
                        Text("YOUR TEAMS & LEAGUES")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktMuted).kerning(1.5)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 16)

                    ForEach(viewModel.suggestedMatches) { match in
                        ArenaMatchCard(match: match).padding(.horizontal, 16)
                    }
                }
                Spacer().frame(height: 80)
            }
        }
    }
}

// MARK: - Live Feed

struct LiveFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.liveMatches.isEmpty {
                    VStack(spacing: 12) {
                        Text("📡").font(.system(size: 44))
                        Text("Nothing live right now").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                        Text("Check back when matches are in progress")
                            .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    }
                    .padding(.top, 100).padding(.horizontal, 40)
                } else {
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(Color.predktCoral).frame(width: 7, height: 7)
                            Text("\(viewModel.liveMatches.count) LIVE NOW")
                                .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral).kerning(1.5)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 16)

                    ForEach(viewModel.liveMatches) { match in
                        ArenaLiveCard(match: match).padding(.horizontal, 16)
                    }
                }
                Spacer().frame(height: 80)
            }
        }
    }
}

// MARK: - Arena Match Card

struct ArenaMatchCard: View {
    let match: Match

    var body: some View {
        HStack(spacing: 14) {
            // Home
            HStack(spacing: 10) {
                TeamBadgeView(url: match.homeLogo)
                Text(match.home)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Centre
            if match.isLive || match.isFinished {
                Text(match.score)
                    .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
            } else {
                VStack(spacing: 1) {
                    Text(match.kickoffTime)
                        .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                    Text("KO").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.6))
                }
            }

            // Away
            HStack(spacing: 10) {
                Text(match.away)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).multilineTextAlignment(.trailing)
                TeamBadgeView(url: match.awayLogo)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Color.predktCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(match.isLive ? Color.predktCoral.opacity(0.3) : Color.predktBorder, lineWidth: 1)
        )
    }
}

// MARK: - Arena Live Card

struct ArenaLiveCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                    Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                        .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral).kerning(1)
                }
                Text("·").foregroundStyle(Color.predktMuted)
                Text(match.competition).font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                Spacer()
            }

            HStack {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home).font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                }
                Spacer()
                Text(match.score).font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 10) {
                    Text(match.away).font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                    TeamBadgeView(url: match.awayLogo)
                }
            }
        }
        .padding(16)
        .background(Color.predktCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktCoral.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Arena Pick Card (social poll look)

struct ArenaPickCard: View {
    let pick: Pick

    private var username: String { pick.profiles?.username ?? pick.username ?? "Player" }
    private var initial: String { String(username.prefix(1)).uppercased() }

    // Simulated community agreement bar
    private var agreePct: Int { max(30, min(85, pick.confidence + Int.random(in: -15...15)) ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User row
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.predktLime.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(Text(initial).font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktLime))

                VStack(alignment: .leading, spacing: 1) {
                    Text(username).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    Text(pick.match).font(.system(size: 11)).foregroundStyle(Color.predktMuted).lineLimit(1)
                }
                Spacer()

                // Result badge
                Text(resultLabel)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(resultColour)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(resultColour.opacity(0.12)).cornerRadius(8)
            }

            // Prediction pill
            HStack(spacing: 6) {
                Text("⚡")
                Text(pick.market)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.predktLime.opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.predktLime.opacity(0.2), lineWidth: 1))

            // Community poll bar
            VStack(spacing: 5) {
                HStack {
                    Text("Community agreement").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                    Spacer()
                    Text("\(agreePct)%").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktLime)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(Color.predktLime)
                            .frame(width: geo.size.width * CGFloat(agreePct) / 100, height: 6)
                    }
                }
                .frame(height: 6)
            }

            // XP
            HStack {
                Text("+\(pick.points_possible) XP")
                    .font(.system(size: 11, weight: .black)).foregroundStyle(Color.predktLime)
                Spacer()
                Text("\(pick.confidence)% confident")
                    .font(.system(size: 11)).foregroundStyle(Color.predktMuted)
            }
        }
        .padding(16)
        .background(Color.predktCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktBorder, lineWidth: 1))
    }

    private var resultLabel: String {
        switch pick.result {
        case "correct": return "✓ CORRECT"
        case "wrong":   return "✗ WRONG"
        default:        return "⏳ PENDING"
        }
    }

    private var resultColour: Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktMuted
        }
    }
}

// MARK: - Interests Prompt

struct ArenaInterestsPrompt: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text("🎯").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalise your Arena")
                        .font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                    Text("Follow teams & leagues you care about")
                        .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.predktLime).font(.system(size: 13, weight: .bold))
            }
            .padding(16)
            .background(Color.predktLime.opacity(0.07))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktLime.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty State

struct ArenaEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🏟️").font(.system(size: 44))
            Text("The arena is quiet").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Text("No plays yet today. Be the first!").font(.system(size: 13)).foregroundStyle(Color.predktMuted)
        }
        .padding(.top, 80)
    }
}
