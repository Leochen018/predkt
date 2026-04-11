import SwiftUI
import Supabase

// MARK: - Data model for a grouped combo block

struct PickComboBlock: Identifiable {
    let id: String           // combo_id or "user_id|match"
    let username: String
    let userId: String
    let matchName: String
    let picks: [Pick]
    var isCombo: Bool  { picks.count > 1 }
    var totalXP: Int   { picks.reduce(0) { $0 + $1.points_possible } }
    var overallResult: String {
        if picks.allSatisfy({ $0.result == "correct" }) { return "correct" }
        if picks.contains(where: { $0.result == "wrong" }) { return "wrong" }
        return "pending"
    }
}

// MARK: - Feed View

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedTab = 0
    let tabs = ["For You", "My Picks", "Following", "🔴 Live"]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARENA").font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Community plays").font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: { viewModel.showInterestsPicker = true }) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Color.predktLime)
                            .font(.system(size: 16)).padding(10)
                            .background(Color.predktLime.opacity(0.12)).cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                            Button(action: { withAnimation { selectedTab = i } }) {
                                VStack(spacing: 6) {
                                    Text(tab).font(.system(size: 13, weight: selectedTab==i ? .bold : .medium))
                                        .foregroundStyle(selectedTab==i ? .white : Color.predktMuted).fixedSize()
                                    Rectangle().fill(selectedTab==i ? Color.predktLime : .clear)
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
        .sheet(isPresented: $viewModel.showInterestsPicker) { InterestsPickerView(viewModel: viewModel) }
    }
}

// MARK: - Grouping helper
// Groups picks into combo blocks using combo_id when available,
// falling back to match + user_id for singles

func groupPicksIntoCombos(_ picks: [Pick]) -> [PickComboBlock] {
    var blocks: [PickComboBlock] = []
    var usedIds = Set<String>()

    // Pass 1: group picks that share a combo_id
    var comboMap: [String: [Pick]] = [:]
    for pick in picks {
        guard let comboId = pick.combo_id, !comboId.isEmpty else { continue }
        comboMap[comboId, default: []].append(pick)
    }
    for (comboId, comboPicks) in comboMap {
        guard !comboPicks.isEmpty else { continue }
        let first    = comboPicks[0]
        let username = first.profiles?.username ?? first.username ?? "Player"
        blocks.append(PickComboBlock(
            id: comboId, username: username, userId: first.user_id,
            matchName: first.match, picks: comboPicks
        ))
        comboPicks.forEach { usedIds.insert($0.id) }
    }

    // Pass 2: group remaining singles by user_id + match
    var singleMap: [String: [Pick]] = [:]
    for pick in picks {
        guard !usedIds.contains(pick.id) else { continue }
        let key = "\(pick.user_id)|\(pick.match)"
        singleMap[key, default: []].append(pick)
    }
    for (key, groupPicks) in singleMap {
        guard !groupPicks.isEmpty else { continue }
        let first    = groupPicks[0]
        let username = first.profiles?.username ?? first.username ?? "Player"
        blocks.append(PickComboBlock(
            id: key, username: username, userId: first.user_id,
            matchName: first.match, picks: groupPicks
        ))
    }

    // Sort: pending first, then by most recent
    return blocks.sorted {
        if $0.overallResult == "pending" && $1.overallResult != "pending" { return true }
        if $0.overallResult != "pending" && $1.overallResult == "pending" { return false }
        return ($0.picks.first?.created_at ?? "") > ($1.picks.first?.created_at ?? "")
    }
}

// MARK: - For You Feed

struct ForYouFeed: View {
    @ObservedObject var viewModel: FeedViewModel

    var comboBlocks: [PickComboBlock] { groupPicksIntoCombos(viewModel.feedPicks) }

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
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.predktLime).kerning(1.5)
                            Spacer()
                        }
                        ForEach(viewModel.suggestedMatches.prefix(4)) { match in
                            ArenaMatchCard(match: match)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !comboBlocks.isEmpty {
                    HStack {
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                        Text("COMMUNITY PLAYS")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2).fixedSize()
                        Rectangle().fill(Color.predktBorder).frame(height: 1)
                    }
                    .padding(.horizontal, 16)

                    ForEach(comboBlocks) { block in
                        CommunityComboCard(block: block)
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

// MARK: - Community Combo Card
// One card = one user's prediction block for a match

struct CommunityComboCard: View {
    let block: PickComboBlock

    private var resultColour: Color {
        switch block.overallResult {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }

    private var resultLabel: String {
        switch block.overallResult {
        case "correct": return "✓ CORRECT"
        case "wrong":   return "✗ WRONG"
        default:        return "⏳ PENDING"
        }
    }

    private func pickColour(_ pick: Pick) -> Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Match name header ─────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "soccerball").font(.system(size: 10)).foregroundStyle(Color.predktLime)
                Text(block.matchName)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktMuted).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            Divider().background(Color.predktBorder)

            // ── User + combo badge ────────────────────────────────────────────
            HStack(spacing: 10) {
                Circle().fill(Color.predktLime.opacity(0.12)).frame(width: 32, height: 32)
                    .overlay(
                        Text(String(block.username.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.username).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    if block.isCombo {
                        Text("\(block.picks.count)-PICK COMBO")
                            .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktLime).kerning(0.5)
                    } else {
                        Text("Single play").font(.system(size: 9)).foregroundStyle(Color.predktMuted)
                    }
                }
                Spacer()
                Text(resultLabel)
                    .font(.system(size: 9, weight: .black)).foregroundStyle(resultColour)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(resultColour.opacity(0.12)).cornerRadius(6)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            // ── Each pick as a pill ───────────────────────────────────────────
            VStack(spacing: 6) {
                ForEach(block.picks) { pick in
                    HStack(spacing: 8) {
                        // Result dot
                        Circle().fill(pickColour(pick)).frame(width: 7, height: 7)

                        Text(pick.market)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(2)

                        Spacer()

                        // XP
                        Text("+\(pick.points_possible) XP")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(pickColour(pick))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(pickColour(pick).opacity(0.07))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(pickColour(pick).opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, 14)

            // ── Footer: total XP ──────────────────────────────────────────────
            HStack {
                Spacer()
                if block.isCombo {
                    HStack(spacing: 4) {
                        Text("COMBO TOTAL").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.predktMuted).kerning(1)
                        Text("+\(block.totalXP) XP")
                            .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
        }
        .background(Color.predktCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(block.isCombo ? Color.predktLime.opacity(0.15) : Color.predktBorder, lineWidth: 1)
        )
    }
}

// MARK: - My Picks Feed

struct MyPicksFeed: View {
    @ObservedObject var viewModel: FeedViewModel
    @State private var confirmDeleteId: String? = nil
    @State private var deletingId: String? = nil
    @State private var toast: String? = nil

    // Group my own picks into combo blocks
    var myBlocks: [PickComboBlock] { groupPicksIntoCombos(viewModel.myPicks) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if viewModel.myPicks.isEmpty {
                        VStack(spacing: 16) {
                            Text("🎯").font(.system(size: 48))
                            Text("No plays today yet")
                                .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                            Text("Head to the Play tab to make your predictions")
                                .font(.system(size: 13)).foregroundStyle(Color.predktMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 80).padding(.horizontal, 40)
                    } else {
                        // Stats bar
                        let correct = viewModel.myPicks.filter { $0.result == "correct" }.count
                        let wrong   = viewModel.myPicks.filter { $0.result == "wrong"   }.count
                        let pending = viewModel.myPicks.filter { $0.result == "pending" }.count
                        let xp      = viewModel.myPicks.compactMap { $0.points_earned }.reduce(0, +)

                        HStack(spacing: 8) {
                            MyStatPill(value: "\(correct)", label: "Correct", colour: Color.predktLime)
                            MyStatPill(value: "\(wrong)",   label: "Wrong",   colour: Color.predktCoral)
                            MyStatPill(value: "\(pending)", label: "Pending", colour: Color.predktAmber)
                            MyStatPill(value: xp >= 0 ? "+\(xp)" : "\(xp)", label: "XP today",
                                       colour: xp >= 0 ? Color.predktLime : Color.predktCoral)
                        }
                        .padding(.horizontal, 16)

                        // Combo blocks
                        ForEach(myBlocks) { block in
                            MyComboCard(
                                block: block,
                                deletingId: deletingId,
                                onDelete: { pick in confirmDeleteId = pick.id }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.top, 16)
            }

            if let msg = toast {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.predktLime).cornerRadius(20).padding(.bottom, 100)
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
                confirmDeleteId = nil; deletingId = id
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
            if let id = confirmDeleteId,
               let pick = viewModel.myPicks.first(where: { $0.id == id }) {
                Text("Remove \"\(pick.market)\"? This can't be undone.")
            }
        }
    }
}

// MARK: - My Combo Card (with remove buttons)

struct MyComboCard: View {
    let block: PickComboBlock
    let deletingId: String?
    let onDelete: (Pick) -> Void

    private func pickColour(_ pick: Pick) -> Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.matchName)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    if block.isCombo {
                        Text("\(block.picks.count)-PICK COMBO")
                            .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktLime).kerning(0.5)
                    }
                }
                Spacer()
                Text("+\(block.totalXP) XP")
                    .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider().background(Color.predktBorder)

            // Picks
            ForEach(block.picks) { pick in
                HStack(spacing: 12) {
                    // Status icon
                    Image(systemName: pick.result == "correct" ? "checkmark.circle.fill"
                          : pick.result == "wrong" ? "xmark.circle.fill" : "clock.fill")
                        .font(.system(size: 18)).foregroundStyle(pickColour(pick)).frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.market)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                        HStack(spacing: 4) {
                            Text(pick.result == "pending" ? "⏳ Pending"
                                 : pick.result == "correct" ? "✓ Correct" : "✗ Wrong")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(pickColour(pick))
                            if let earned = pick.points_earned {
                                Text("· \(earned >= 0 ? "+" : "")\(earned) XP")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(earned >= 0 ? Color.predktLime : Color.predktCoral)
                            } else {
                                Text("· +\(pick.points_possible) XP possible")
                                    .font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                            }
                        }
                    }

                    Spacer()

                    // Remove button (only pending)
                    if pick.result == "pending" {
                        if deletingId == pick.id {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.predktCoral))
                                .scaleEffect(0.8)
                        } else {
                            Button(action: { onDelete(pick) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "trash").font(.system(size: 10))
                                    Text("Remove").font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(Color.predktCoral)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color.predktCoral.opacity(0.1)).cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.predktCoral.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .opacity(deletingId == pick.id ? 0.4 : 1.0)

                if pick.id != block.picks.last?.id {
                    Divider().background(Color.predktBorder.opacity(0.4)).padding(.leading, 52)
                }
            }

            Spacer().frame(height: 10)
        }
        .background(Color.predktCard).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(block.isCombo ? Color.predktLime.opacity(0.15) : Color.predktBorder, lineWidth: 1))
    }
}

struct MyStatPill: View {
    let value: String; let label: String; let colour: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black)).foregroundStyle(colour)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.predktCard).cornerRadius(12)
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
        let sorted = viewModel.suggestedMatches.sorted {
            $0.rawDate == $1.rawDate ? $0.competition < $1.competition : $0.rawDate < $1.rawDate
        }
        var dayMap: [String: [Match]] = [:]; var dayOrder: [String] = []
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
            guard let matches = dayMap[key], let first = matches.first else { return nil }
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            let date = f1.date(from: first.rawDate) ?? f2.date(from: first.rawDate) ?? Date()
            let df   = DateFormatter(); df.timeZone = .current; df.dateFormat = "EEEE d MMMM"
            var leagueOrder: [String] = []; var leagueMap: [String: [Match]] = [:]
            for m in matches {
                if leagueMap[m.competition] == nil { leagueOrder.append(m.competition); leagueMap[m.competition] = [] }
                leagueMap[m.competition]!.append(m)
            }
            let leagueGroups = leagueOrder.map {
                (league: $0, matches: leagueMap[$0]!.sorted { $0.rawDate < $1.rawDate })
            }
            return DateGroup(id: key, displayDate: df.string(from: date),
                             isToday: cal.isDateInToday(date), leagueGroups: leagueGroups)
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
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.predktLime).cornerRadius(20)
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
                                        Text("TODAY").font(.system(size: 11, weight: .black))
                                            .foregroundStyle(Color.predktLime).kerning(2)
                                    }
                                    Text(dayGroup.displayDate)
                                        .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                                }
                                Spacer()
                                let total = dayGroup.leagueGroups.reduce(0) { $0 + $1.matches.count }
                                Text("\(total) match\(total == 1 ? "" : "es")")
                                    .font(.system(size: 11)).foregroundStyle(Color.predktMuted).padding(.bottom, 4)
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
                Text(league.uppercased()).font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.predktMuted).kerning(1)
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
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                } else if match.isFinished {
                    Text("FULL TIME").font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktMuted)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Color.predktLime)
                        Text("Kick off \(match.kickoffTime)")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.predktLime)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.homeLogo).frame(width: 36, height: 36)
                    Text(match.home).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                if match.isLive || match.isFinished {
                    Text(match.score).font(.system(size: 22, weight: .black)).foregroundStyle(.white).frame(width: 70)
                } else {
                    Text("VS").font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktMuted).frame(width: 70)
                }
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.awayLogo).frame(width: 36, height: 36)
                    Text(match.away).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
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
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(match.isLive ? Color.predktCoral.opacity(0.4) : Color.predktBorder, lineWidth: 1))
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
                        Text("Nothing live right now")
                            .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
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

// MARK: - Shared components

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
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktCoral)
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
                }.frame(maxWidth: .infinity, alignment: .leading)
                if match.isLive || match.isFinished {
                    Text(match.score).font(.system(size: 15, weight: .black)).foregroundStyle(.white).frame(width: 56)
                } else {
                    VStack(spacing: 1) {
                        Text(match.kickoffTime).font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                        Text("KO").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.6))
                    }.frame(width: 56)
                }
                HStack(spacing: 10) {
                    Text(match.away).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).multilineTextAlignment(.trailing)
                    TeamBadgeView(url: match.awayLogo)
                }.frame(maxWidth: .infinity, alignment: .trailing)
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
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(match.isLive ? Color.predktCoral.opacity(0.3) : Color.predktBorder, lineWidth: 1))
    }
}

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
            Text("⚽").font(.system(size: 44))
            Text("The arena is quiet").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Text("No plays yet today. Be the first!").font(.system(size: 13)).foregroundStyle(Color.predktMuted)
        }
        .padding(.top, 80)
    }
}
