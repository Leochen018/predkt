import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedTab = 0
    let tabs = ["For You", "Following", "🔴 Live"]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARENA").font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Community plays").font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Color.predktLime).font(.system(size: 16))
                            .padding(10).background(Color.predktLime.opacity(0.12)).cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                        Button(action: { withAnimation { selectedTab = i } }) {
                            VStack(spacing: 6) {
                                Text(tab).font(.system(size: 13, weight: selectedTab == i ? .bold : .medium))
                                    .foregroundStyle(selectedTab == i ? .white : Color.predktMuted)
                                Rectangle().fill(selectedTab == i ? Color.predktLime : .clear).frame(height: 2).cornerRadius(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16).background(Color.predktCard.opacity(0.6))

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

    var groupedPicks: [(match: String, picks: [Pick])] {
        var groups: [(match: String, picks: [Pick])] = []
        var seen: [String: Int] = [:]
        for pick in viewModel.feedPicks {
            if let idx = seen[pick.match] { groups[idx].picks.append(pick) }
            else { seen[pick.match] = groups.count; groups.append((match: pick.match, picks: [pick])) }
        }
        return groups
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if viewModel.followedLeagueIds.isEmpty && viewModel.followedTeamNames.isEmpty {
                    ArenaInterestsPrompt(onTap: { viewModel.showInterestsPicker = true })
                }
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
                if !viewModel.feedPicks.isEmpty {
                    HStack {
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                        Text("COMMUNITY PLAYS").font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktMuted).kerning(2).fixedSize()
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                    ForEach(groupedPicks, id: \.match) { group in
                        GroupedPicksCard(matchName: group.match, picks: group.picks).padding(.horizontal, 16)
                    }
                }
                if viewModel.feedPicks.isEmpty && viewModel.suggestedMatches.isEmpty { ArenaEmptyState() }
                Spacer().frame(height: 80)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Following Feed ✅ REDESIGNED

struct FollowingFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    // Group by date, then within each date by league
    struct DateGroup: Identifiable {
        let id: String      // date string as key
        let displayDate: String
        let isToday: Bool
        let leagueGroups: [(league: String, matches: [Match])]
    }

    var dateGroups: [DateGroup] {
        guard !viewModel.suggestedMatches.isEmpty else { return [] }

        // Sort all matches by date then league
        let sorted = viewModel.suggestedMatches.sorted { m1, m2 in
            if m1.rawDate == m2.rawDate { return m1.competition < m2.competition }
            return m1.rawDate < m2.rawDate
        }

        // Group by calendar day
        var dayMap: [String: [Match]] = [:]
        var dayOrder: [String] = []
        let cal = Calendar.current

        for match in sorted {
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            let date = f1.date(from: match.rawDate) ?? f2.date(from: match.rawDate) ?? Date()
            let key  = cal.startOfDay(for: date).description

            if dayMap[key] == nil { dayOrder.append(key); dayMap[key] = [] }
            dayMap[key]!.append(match)
        }

        return dayOrder.compactMap { key -> DateGroup? in
            guard let matches = dayMap[key], let firstMatch = matches.first else { return nil }

            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            let date = f1.date(from: firstMatch.rawDate) ?? f2.date(from: firstMatch.rawDate) ?? Date()

            let df = DateFormatter(); df.timeZone = .current
            df.dateFormat = "EEEE d MMMM"   // e.g. "Saturday 12 April"
            let displayDate = df.string(from: date)
            let isToday = cal.isDateInToday(date)

            // Group matches by league within this day
            var leagueOrder: [String] = []
            var leagueMap: [String: [Match]] = [:]
            for m in matches {
                if leagueMap[m.competition] == nil { leagueOrder.append(m.competition); leagueMap[m.competition] = [] }
                leagueMap[m.competition]!.append(m)
            }
            let leagueGroups = leagueOrder.map { league in
                (league: league, matches: leagueMap[league]!.sorted { $0.rawDate < $1.rawDate })
            }

            return DateGroup(id: key, displayDate: displayDate, isToday: isToday, leagueGroups: leagueGroups)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if dateGroups.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Text("❤️").font(.system(size: 48))
                    Text("No upcoming matches")
                        .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                    Text("Follow teams and leagues to see their fixtures here")
                        .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Text("Choose Interests")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.predktLime).cornerRadius(20)
                    }
                }
                .padding(.top, 80).padding(.horizontal, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(dateGroups) { dayGroup in
                        // ✅ Big bold date header
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .bottom, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if dayGroup.isToday {
                                        Text("TODAY")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(Color.predktLime)
                                            .kerning(2)
                                    }
                                    Text(dayGroup.displayDate)
                                        .font(.system(size: 22, weight: .black))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                // Match count for this day
                                let total = dayGroup.leagueGroups.reduce(0) { $0 + $1.matches.count }
                                Text("\(total) match\(total == 1 ? "" : "es")")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.predktMuted)
                                    .padding(.bottom, 4)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 12)

                            // Matches grouped by league within this day
                            ForEach(dayGroup.leagueGroups, id: \.league) { leagueGroup in
                                FollowingLeagueSection(league: leagueGroup.league, matches: leagueGroup.matches)
                            }
                        }
                    }
                    Spacer().frame(height: 80)
                }
            }
        }
    }
}

// MARK: - Following League Section

struct FollowingLeagueSection: View {
    let league: String
    let matches: [Match]

    var body: some View {
        VStack(spacing: 0) {
            // League label
            HStack(spacing: 8) {
                Rectangle().fill(Color.predktLime).frame(width: 3, height: 14).cornerRadius(2)
                Text(league.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.predktMuted).kerning(1)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color.predktCard.opacity(0.3))

            // Match cards
            VStack(spacing: 8) {
                ForEach(matches, id: \.id) { match in
                    FollowingMatchCard(match: match)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

// MARK: - Following Match Card (date + time + venue prominent)

struct FollowingMatchCard: View {
    let match: Match

    var body: some View {
        VStack(spacing: 0) {
            // Time / status bar
            HStack {
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                } else if match.isFinished {
                    Text("FULL TIME")
                        .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktMuted)
                } else {
                    // ✅ Big clear kickoff time
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Color.predktLime)
                        Text("Kick off \(match.kickoffTime)")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.predktLime)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            // Teams
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.homeLogo).frame(width: 36, height: 36)
                    Text(match.home)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                if match.isLive || match.isFinished {
                    Text(match.score)
                        .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                        .frame(width: 70)
                } else {
                    Text("VS")
                        .font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktMuted)
                        .frame(width: 70)
                }

                VStack(spacing: 6) {
                    TeamBadgeView(url: match.awayLogo).frame(width: 36, height: 36)
                    Text(match.away)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14).padding(.bottom, 10)

            // Venue
            if let venue = match.venue, !venue.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                    Text(venue).font(.system(size: 10)).foregroundStyle(Color.predktMuted).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                Spacer().frame(height: 10)
            }
        }
        .background(Color.predktCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(match.isLive ? Color.predktCoral.opacity(0.4) : Color.predktBorder, lineWidth: 1))
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
                        Text("Check back when matches are in progress").font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    }
                    .padding(.top, 100).padding(.horizontal, 40)
                } else {
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(Color.predktCoral).frame(width: 7, height: 7)
                            Text("\(viewModel.liveMatches.count) LIVE NOW").font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral).kerning(1.5)
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

// MARK: - Grouped Picks Card

struct GroupedPicksCard: View {
    let matchName: String
    let picks: [Pick]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "soccerball").font(.system(size: 11)).foregroundStyle(Color.predktLime)
                Text(matchName).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("\(picks.count) play\(picks.count == 1 ? "" : "s")").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
            }
            .padding(.bottom, 4)
            Divider().background(Color.predktBorder)
            ForEach(picks) { pick in
                PickRow(pick: pick)
                if pick.id != picks.last?.id { Divider().background(Color.predktBorder.opacity(0.5)) }
            }
        }
        .padding(16).background(Color.predktCard).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktBorder, lineWidth: 1))
    }
}

struct PickRow: View {
    let pick: Pick
    private var username: String { pick.profiles?.username ?? pick.username ?? "Player" }
    private var agreePct: Int { min(95, max(30, pick.confidence + Int.random(in: -10...10))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.predktLime.opacity(0.12)).frame(width: 28, height: 28)
                    .overlay(Text(String(username.prefix(1)).uppercased()).font(.system(size: 11, weight: .black)).foregroundStyle(Color.predktLime))
                Text(username).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(resultLabel).font(.system(size: 9, weight: .black)).foregroundStyle(resultColour)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(resultColour.opacity(0.12)).cornerRadius(6)
            }
            HStack(spacing: 6) {
                Text("⚡ \(pick.market)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Color.predktLime.opacity(0.1)).cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.predktLime.opacity(0.2), lineWidth: 1))
                Spacer()
                Text("+\(pick.points_possible) XP").font(.system(size: 11, weight: .black)).foregroundStyle(Color.predktLime)
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Community agreement").font(.system(size: 9)).foregroundStyle(Color.predktMuted)
                    Spacer()
                    Text("\(agreePct)%").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktLime)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3).fill(Color.predktLime).frame(width: geo.size.width * CGFloat(agreePct) / 100, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
    }
    private var resultLabel: String { pick.result == "correct" ? "✓ CORRECT" : pick.result == "wrong" ? "✗ WRONG" : "⏳ PENDING" }
    private var resultColour: Color { pick.result == "correct" ? Color.predktLime : pick.result == "wrong" ? Color.predktCoral : Color.predktMuted }
}

// MARK: - Arena Match Card (For You tab)

struct ArenaMatchCard: View {
    let match: Match
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(match.competition).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.predktMuted)
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.predktCoral).frame(width: 5, height: 5)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")").font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                } else {
                    Text(match.matchDate).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktLime)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo)
                    Text(match.home).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if match.isLive || match.isFinished {
                    Text(match.score).font(.system(size: 15, weight: .black)).foregroundStyle(.white).frame(width: 56)
                } else {
                    VStack(spacing: 1) {
                        Text(match.kickoffTime).font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                        Text("KO").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.6))
                    }
                    .frame(width: 56)
                }
                HStack(spacing: 10) {
                    Text(match.away).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1).multilineTextAlignment(.trailing)
                    TeamBadgeView(url: match.awayLogo)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            if let venue = match.venue, !venue.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                    Text(venue).font(.system(size: 10)).foregroundStyle(Color.predktMuted).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 12)
            } else { Spacer().frame(height: 12) }
        }
        .background(Color.predktCard).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(match.isLive ? Color.predktCoral.opacity(0.3) : Color.predktBorder, lineWidth: 1))
    }
}

struct ArenaLiveCard: View {
    let match: Match
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                    Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")").font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral).kerning(1)
                }
                Text("·").foregroundStyle(Color.predktMuted)
                Text(match.competition).font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                Spacer()
            }
            HStack {
                HStack(spacing: 10) { TeamBadgeView(url: match.homeLogo); Text(match.home).font(.system(size: 16, weight: .black)).foregroundStyle(.white) }
                Spacer()
                Text(match.score).font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 10) { Text(match.away).font(.system(size: 16, weight: .black)).foregroundStyle(.white); TeamBadgeView(url: match.awayLogo) }
            }
        }
        .padding(16).background(Color.predktCard).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktCoral.opacity(0.2), lineWidth: 1))
    }
}

struct ArenaInterestsPrompt: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text("🎯").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalise your Arena").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                    Text("Follow teams & leagues you care about").font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.predktLime).font(.system(size: 13, weight: .bold))
            }
            .padding(16).background(Color.predktLime.opacity(0.07)).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktLime.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle()).padding(.horizontal, 16)
    }
}

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
