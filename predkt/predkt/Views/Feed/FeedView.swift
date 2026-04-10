import SwiftUI
import Supabase

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedTab = 0
    let tabs = ["For You", "My Picks", "Following", "🔴 Live"]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
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

                // Tabs — scrollable so all 4 fit
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                            Button(action: { withAnimation { selectedTab = i } }) {
                                VStack(spacing: 6) {
                                    Text(tab)
                                        .font(.system(size: 13, weight: selectedTab == i ? .bold : .medium))
                                        .foregroundStyle(selectedTab == i ? .white : Color.predktMuted)
                                        .fixedSize()
                                    Rectangle()
                                        .fill(selectedTab == i ? Color.predktLime : .clear)
                                        .frame(height: 2).cornerRadius(1)
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .background(Color.predktCard.opacity(0.6))

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.predktLime))
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        ForYouFeed(viewModel: viewModel).tag(0)
                        MyPicksFeed(viewModel: viewModel).tag(1)
                        FollowingFeed(viewModel: viewModel).tag(2)
                        LiveFeed(viewModel: viewModel).tag(3)
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
                        CommunityGroupCard(matchName: group.match, picks: group.picks)
                            .padding(.horizontal, 16)
                    }
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

// MARK: - Community Group Card (read-only, no delete)

struct CommunityGroupCard: View {
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
                CommunityPickRow(pick: pick)
                if pick.id != picks.last?.id { Divider().background(Color.predktBorder.opacity(0.4)) }
            }
        }
        .padding(16).background(Color.predktCard).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktBorder, lineWidth: 1))
    }
}

struct CommunityPickRow: View {
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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(Color.predktLime)
                        .frame(width: geo.size.width * CGFloat(agreePct) / 100, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
    private var resultLabel: String { pick.result == "correct" ? "✓ CORRECT" : pick.result == "wrong" ? "✗ WRONG" : "⏳ PENDING" }
    private var resultColour: Color { pick.result == "correct" ? Color.predktLime : pick.result == "wrong" ? Color.predktCoral : Color.predktMuted }
}

// MARK: - My Picks Feed ✅ NEW TAB

struct MyPicksFeed: View {
    @ObservedObject var viewModel: FeedViewModel
    @State private var confirmDeleteId: String? = nil
    @State private var deletingId: String? = nil
    @State private var toast: String? = nil

    // Group my picks by match
    var myGrouped: [(match: String, picks: [Pick])] {
        var groups: [(match: String, picks: [Pick])] = []
        var seen: [String: Int] = [:]
        for pick in viewModel.myPicks {
            if let idx = seen[pick.match] { groups[idx].picks.append(pick) }
            else { seen[pick.match] = groups.count; groups.append((match: pick.match, picks: [pick])) }
        }
        return groups
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if viewModel.myPicks.isEmpty {
                        VStack(spacing: 16) {
                            Text("🎯").font(.system(size: 48))
                            Text("No plays today yet").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                            Text("Head to the Play tab to make your first prediction of the day")
                                .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                        }
                        .padding(.top, 80).padding(.horizontal, 40)
                    } else {
                        // Stats bar
                        let correct = viewModel.myPicks.filter { $0.result == "correct" }.count
                        let wrong   = viewModel.myPicks.filter { $0.result == "wrong"   }.count
                        let pending = viewModel.myPicks.filter { $0.result == "pending" }.count
                        let xp      = viewModel.myPicks.compactMap { $0.points_earned }.reduce(0, +)

                        HStack(spacing: 0) {
                            MyStatPill(value: "\(correct)", label: "Correct", colour: Color.predktLime)
                            MyStatPill(value: "\(wrong)",   label: "Wrong",   colour: Color.predktCoral)
                            MyStatPill(value: "\(pending)", label: "Pending", colour: Color.predktAmber)
                            MyStatPill(value: xp >= 0 ? "+\(xp)" : "\(xp)", label: "XP today", colour: xp >= 0 ? Color.predktLime : Color.predktCoral)
                        }
                        .padding(.horizontal, 16)

                        ForEach(myGrouped, id: \.match) { group in
                            MyPicksGroupCard(
                                matchName: group.match,
                                picks: group.picks,
                                deletingId: deletingId,
                                onDelete: { pick in
                                    confirmDeleteId = pick.id
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.top, 16)
            }

            // Toast
            if let msg = toast {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.predktLime).cornerRadius(20)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toast)
        .alert("Remove this play?", isPresented: Binding(
            get: { confirmDeleteId != nil },
            set: { if !$0 { confirmDeleteId = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let id = confirmDeleteId,
                      let pick = viewModel.myPicks.first(where: { $0.id == id }) else { return }
                confirmDeleteId = nil
                deletingId = id
                Task {
                    await viewModel.deletePick(pick)
                    deletingId = nil
                    withAnimation { toast = "Play removed ✓" }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { toast = nil }
                }
            }
            Button("Keep it", role: .cancel) { confirmDeleteId = nil }
        } message: {
            if let id = confirmDeleteId, let pick = viewModel.myPicks.first(where: { $0.id == id }) {
                Text("Remove \"\(pick.market)\"? This can't be undone.")
            }
        }
    }
}

struct MyStatPill: View {
    let value: String; let label: String; let colour: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black)).foregroundStyle(colour)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.predktCard)
        .cornerRadius(12)
    }
}

// MARK: - My Picks Group Card (with explicit remove buttons)

struct MyPicksGroupCard: View {
    let matchName: String
    let picks: [Pick]
    let deletingId: String?
    let onDelete: (Pick) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Match header
            HStack(spacing: 8) {
                Image(systemName: "soccerball").font(.system(size: 11)).foregroundStyle(Color.predktLime)
                Text(matchName).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("\(picks.count) play\(picks.count == 1 ? "" : "s")").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
            }
            .padding(16)

            Divider().background(Color.predktBorder)

            ForEach(picks) { pick in
                MyPickRow(pick: pick, isDeleting: deletingId == pick.id, onDelete: { onDelete(pick) })
                if pick.id != picks.last?.id { Divider().background(Color.predktBorder.opacity(0.4)).padding(.leading, 16) }
            }
        }
        .background(Color.predktCard).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktBorder, lineWidth: 1))
    }
}

// MARK: - My Pick Row (explicit remove button, no swipe)

struct MyPickRow: View {
    let pick: Pick
    let isDeleting: Bool
    let onDelete: () -> Void

    private var canDelete: Bool { pick.result == "pending" }

    private var statusColour: Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }
    private var statusIcon: String {
        switch pick.result {
        case "correct": return "checkmark.circle.fill"
        case "wrong":   return "xmark.circle.fill"
        default:        return "clock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 22)).foregroundStyle(statusColour)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(pick.market)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 6) {
                    Text(pick.result == "pending" ? "⏳ Pending" : pick.result == "correct" ? "✓ Correct" : "✗ Wrong")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(statusColour)
                    if let earned = pick.points_earned {
                        Text("·").foregroundStyle(Color.predktMuted)
                        Text(earned >= 0 ? "+\(earned) XP" : "\(earned) XP")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(earned >= 0 ? Color.predktLime : Color.predktCoral)
                    } else {
                        Text("·").foregroundStyle(Color.predktMuted)
                        Text("+\(pick.points_possible) XP possible")
                            .font(.system(size: 11)).foregroundStyle(Color.predktMuted)
                    }
                }
            }

            Spacer()

            // ✅ Explicit remove button — always visible for pending picks
            if canDelete {
                if isDeleting {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.predktCoral))
                        .scaleEffect(0.8)
                } else {
                    Button(action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash").font(.system(size: 11))
                            Text("Remove").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.predktCoral)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.predktCoral.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.predktCoral.opacity(0.25), lineWidth: 1))
                    }
                }
            }
        }
        .padding(16)
        .opacity(isDeleting ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isDeleting)
    }
}

// MARK: - Following Feed

struct FollowingFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    struct DateGroup: Identifiable {
        let id: String; let displayDate: String; let isToday: Bool
        let leagueGroups: [(league: String, matches: [Match])]
    }

    var dateGroups: [DateGroup] {
        guard !viewModel.suggestedMatches.isEmpty else { return [] }
        let sorted = viewModel.suggestedMatches.sorted { $0.rawDate == $1.rawDate ? $0.competition < $1.competition : $0.rawDate < $1.rawDate }
        var dayMap: [String: [Match]] = [:]; var dayOrder: [String] = []
        let cal = Calendar.current
        for match in sorted {
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            let date = f1.date(from: match.rawDate) ?? f2.date(from: match.rawDate) ?? Date()
            let key = cal.startOfDay(for: date).description
            if dayMap[key] == nil { dayOrder.append(key); dayMap[key] = [] }
            dayMap[key]!.append(match)
        }
        return dayOrder.compactMap { key -> DateGroup? in
            guard let matches = dayMap[key], let first = matches.first else { return nil }
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            let date = f1.date(from: first.rawDate) ?? f2.date(from: first.rawDate) ?? Date()
            let df = DateFormatter(); df.timeZone = .current; df.dateFormat = "EEEE d MMMM"
            var leagueOrder: [String] = []; var leagueMap: [String: [Match]] = [:]
            for m in matches {
                if leagueMap[m.competition] == nil { leagueOrder.append(m.competition); leagueMap[m.competition] = [] }
                leagueMap[m.competition]!.append(m)
            }
            let leagueGroups = leagueOrder.map { (league: $0, matches: leagueMap[$0]!.sorted { $0.rawDate < $1.rawDate }) }
            return DateGroup(id: key, displayDate: df.string(from: date), isToday: cal.isDateInToday(date), leagueGroups: leagueGroups)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if dateGroups.isEmpty {
                VStack(spacing: 20) {
                    Text("❤️").font(.system(size: 48))
                    Text("No upcoming matches").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                    Text("Follow teams and leagues to see their fixtures here")
                        .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Text("Choose Interests").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 24).padding(.vertical, 12).background(Color.predktLime).cornerRadius(20)
                    }
                }
                .padding(.top, 80).padding(.horizontal, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(dateGroups) { dayGroup in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if dayGroup.isToday {
                                        Text("TODAY").font(.system(size: 11, weight: .black)).foregroundStyle(Color.predktLime).kerning(2)
                                    }
                                    Text(dayGroup.displayDate).font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                                }
                                Spacer()
                                let total = dayGroup.leagueGroups.reduce(0) { $0 + $1.matches.count }
                                Text("\(total) match\(total == 1 ? "" : "es")").font(.system(size: 11)).foregroundStyle(Color.predktMuted).padding(.bottom, 4)
                            }
                            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)

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

struct FollowingLeagueSection: View {
    let league: String; let matches: [Match]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(Color.predktLime).frame(width: 3, height: 14).cornerRadius(2)
                Text(league.uppercased()).font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktMuted).kerning(1)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8).background(Color.predktCard.opacity(0.3))
            VStack(spacing: 8) {
                ForEach(matches, id: \.id) { match in FollowingMatchCard(match: match) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

struct FollowingMatchCard: View {
    let match: Match
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")").font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                } else if match.isFinished {
                    Text("FULL TIME").font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktMuted)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Color.predktLime)
                        Text("Kick off \(match.kickoffTime)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.predktLime)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.homeLogo).frame(width: 36, height: 36)
                    Text(match.home).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                if match.isLive || match.isFinished {
                    Text(match.score).font(.system(size: 22, weight: .black)).foregroundStyle(.white).frame(width: 70)
                } else {
                    Text("VS").font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktMuted).frame(width: 70)
                }
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.awayLogo).frame(width: 36, height: 36)
                    Text(match.away).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14).padding(.bottom, 10)

            if let venue = match.venue, !venue.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                    Text(venue).font(.system(size: 10)).foregroundStyle(Color.predktMuted).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            } else { Spacer().frame(height: 10) }
        }
        .background(Color.predktCard).cornerRadius(14)
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

// MARK: - Shared components

struct ArenaMatchCard: View {
    let match: Match
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(match.competition).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.predktMuted)
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) { Circle().fill(Color.predktCoral).frame(width: 5, height: 5); Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")").font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral) }
                } else { Text(match.matchDate).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktLime) }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            HStack(spacing: 0) {
                HStack(spacing: 10) { TeamBadgeView(url: match.homeLogo); Text(match.home).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                if match.isLive || match.isFinished { Text(match.score).font(.system(size: 15, weight: .black)).foregroundStyle(.white).frame(width: 56) }
                else { VStack(spacing: 1) { Text(match.kickoffTime).font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime); Text("KO").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.6)) }.frame(width: 56) }
                HStack(spacing: 10) { Text(match.away).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1).multilineTextAlignment(.trailing); TeamBadgeView(url: match.awayLogo) }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            if let venue = match.venue, !venue.isEmpty {
                HStack(spacing: 4) { Image(systemName: "mappin.circle.fill").font(.system(size: 10)).foregroundStyle(Color.predktMuted); Text(venue).font(.system(size: 10)).foregroundStyle(Color.predktMuted).lineLimit(1) }
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
                HStack(spacing: 5) { Circle().fill(Color.predktCoral).frame(width: 6, height: 6); Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")").font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral).kerning(1) }
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
