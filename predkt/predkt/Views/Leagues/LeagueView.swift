import SwiftUI
import Combine
import Supabase
import PostgREST
import Auth

// MARK: - Cached League Info

fileprivate struct CachedLeagueInfo {
    var userRank: Int
    var memberCount: Int
    var totalXP: Int
}

// MARK: - League View

struct LeagueView: View {
    @StateObject private var viewModel = LeagueViewModel()
    @EnvironmentObject var supabaseManager: SupabaseManager

    @State private var leagueInfoCache: [String: CachedLeagueInfo] = [:]
    @State private var publicTab = 0  // 0 = Trending (weekly), 1 = Global (all-time)
    @State private var showLeagueDetail = false

    private var currentUserId: String? {
        supabaseManager.user?.id.uuidString.lowercased()
    }

    private var myGlobalRank: Int? {
        guard let uid = currentUserId else { return nil }
        return viewModel.globalLeaderboard.firstIndex { $0.id == uid }.map { $0 + 1 }
    }

    private var topPercent: Int? {
        guard let rank = myGlobalRank, viewModel.globalLeaderboard.count > 1 else { return nil }
        let pct = Double(rank) / Double(viewModel.globalLeaderboard.count) * 100
        return max(1, Int(ceil(pct)))
    }

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            if viewModel.isLoading && viewModel.globalLeaderboard.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.predktLime))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 28)

                        mySquadsSection

                        globalRankingsSection
                            .padding(.top, 28)

                        Spacer().frame(height: 100)
                    }
                }
            }
        }
        .onAppear { Task { await viewModel.load() } }
        .task(id: viewModel.myLeagues.count) { await loadLeagueDetails() }
        .sheet(isPresented: $showLeagueDetail) {
            if let league = viewModel.selectedLeague {
                LeagueDetailView(league: league, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showCreateLeague) { CreateLeagueSheet(viewModel: viewModel) }
        .sheet(isPresented: $viewModel.showJoinLeague)   { JoinLeagueSheet(viewModel: viewModel) }
        .alert("", isPresented: Binding(
            get: { viewModel.actionMessage != nil },
            set: { if !$0 { viewModel.actionMessage = nil } }
        )) {
            Button("OK") { viewModel.actionMessage = nil }
        } message: { Text(viewModel.actionMessage ?? "") }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GLOBAL STANDING")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.predktLime).kerning(2)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Group {
                    if let rank = myGlobalRank {
                        Text("#\(rank.formatted())")
                    } else {
                        Text("–")
                    }
                }
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(.white)

                if let pct = topPercent {
                    Text("TOP \(pct)%")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color.predktMuted)
                        .kerning(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.predktCard)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.predktBorder, lineWidth: 1))
                }
            }

            Button(action: { viewModel.showCreateLeague = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                    Text("CREATE A SQUAD")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.black).kerning(1.2)
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.predktLime)
                .cornerRadius(12)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - My Squads Section

    private var mySquadsSection: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.predktLime)
                        .frame(width: 3, height: 18)
                        .cornerRadius(2)
                    Text("MY SQUADS")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white).kerning(1.5)
                }
                Spacer()
                if !viewModel.myLeagues.isEmpty {
                    Text("\(viewModel.myLeagues.count) ACTIVE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.predktMuted).kerning(1)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(viewModel.myLeagues) { league in
                    SquadCard(
                        league: league,
                        info: leagueInfoCache[league.id],
                        onTap: {
                            Task {
                                await viewModel.fetchLeagueLeaderboard(for: league)
                                showLeagueDetail = true
                            }
                        }
                    )
                }
                StartNewSquadCard(onCreateTap: { viewModel.showCreateLeague = true },
                                  onJoinTap:   { viewModel.showJoinLeague = true })
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Global Rankings Section

    private var globalRankingsSection: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.predktLime)
                        .frame(width: 3, height: 18)
                        .cornerRadius(2)
                    Text("GLOBAL RANKINGS")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white).kerning(1.5)
                }
                Spacer()
                // Trending / Global toggle
                HStack(spacing: 2) {
                    ForEach(["TRENDING", "ALL TIME"].indices, id: \.self) { i in
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { publicTab = i } }) {
                            Text(["TRENDING", "ALL TIME"][i])
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(publicTab == i ? .black : Color.predktMuted)
                                .kerning(0.5)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(publicTab == i ? Color.predktLime : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(3)
                .background(Color.predktCard)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.predktBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20).padding(.bottom, 14)

            let entries = publicTab == 0
                ? viewModel.weeklyLeaderboard
                : viewModel.globalLeaderboard

            VStack(spacing: 0) {
                ForEach(Array(entries.prefix(10).enumerated()), id: \.element.id) { i, entry in
                    RankingRow(
                        rank: i + 1,
                        entry: entry,
                        xp: publicTab == 0 ? entry.weeklyXP : entry.displayXP,
                        isCurrentUser: entry.id == currentUserId
                    )
                    if i < min(9, entries.count - 1) {
                        Divider()
                            .background(Color.predktBorder)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .background(Color.predktCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.predktBorder, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - League Detail Loader

    private func loadLeagueDetails() async {
        guard !viewModel.myLeagues.isEmpty else { return }
        let uid = currentUserId
        for league in viewModel.myLeagues {
            guard leagueInfoCache[league.id] == nil else { continue }
            do {
                let response = try await SupabaseManager.shared.client
                    .from("league_members")
                    .select("user_id, profiles(id, total_points)")
                    .eq("league_id", value: league.id)
                    .execute()
                struct MP: Decodable {
                    let user_id: String
                    struct P: Decodable { let id: String; let total_points: Int? }
                    let profiles: P?
                }
                let members = try JSONDecoder().decode([MP].self, from: response.data)
                let sorted = members.compactMap { $0.profiles }
                    .sorted { ($0.total_points ?? 0) > ($1.total_points ?? 0) }
                let totalXP = sorted.reduce(0) { $0 + ($1.total_points ?? 0) }
                let rankIdx = sorted.firstIndex { $0.id == uid } ?? -1
                leagueInfoCache[league.id] = CachedLeagueInfo(
                    userRank: rankIdx + 1,
                    memberCount: sorted.count,
                    totalXP: totalXP
                )
            } catch {}
        }
    }
}

// MARK: - Squad Card

fileprivate struct SquadCard: View {
    let league: League
    let info: CachedLeagueInfo?
    let onTap: () -> Void

    private let icons = ["person.3.fill", "shield.fill", "star.fill", "bolt.fill", "flame.fill"]
    private var iconName: String { icons[abs(league.id.hashValue) % icons.count] }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.predktCard)
                    .frame(height: 172)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.predktBorder, lineWidth: 1))

                // Subtle gradient fade
                LinearGradient(
                    colors: [Color.predktLime.opacity(0.0), Color.predktLime.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .cornerRadius(16)
                .frame(height: 172)

                // Top row: icon + prize pool
                VStack {
                    HStack(alignment: .top) {
                        // Icon badge
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.predktLime.opacity(0.1))
                                .frame(width: 44, height: 44)
                            Image(systemName: iconName)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.predktLime)
                        }

                        Spacer()

                        // XP Pool
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("XP POOL")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(Color.predktMuted).kerning(1)
                            if let info = info {
                                Text("\(info.totalXP.formatted()) PTS")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(Color.predktLime)
                            } else {
                                Text("– PTS")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(Color.predktMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 16)

                    Spacer()
                }
                .frame(height: 172)

                // Bottom: league name + rank
                VStack(alignment: .leading, spacing: 4) {
                    Text(league.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)

                    if let info = info {
                        let rankStr = info.userRank > 0 ? "\(info.userRank)" : "–"
                        Text("RANK: \(rankStr) / \(info.memberCount) MEMBERS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktMuted).kerning(0.5)
                    } else {
                        Text("LOADING...")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktMuted).kerning(0.5)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Start New Squad Card

fileprivate struct StartNewSquadCard: View {
    let onCreateTap: () -> Void
    let onJoinTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Create
            Button(action: onCreateTap) {
                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                    Text("START NEW\nPRIVATE LEAGUE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.predktMuted)
                        .multilineTextAlignment(.center).kerning(0.5)
                }
                .frame(maxWidth: .infinity).frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.predktCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(Color.predktBorder)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Join
            Button(action: onJoinTap) {
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.predktAmber)
                    Text("JOIN WITH\nINVITE CODE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.predktMuted)
                        .multilineTextAlignment(.center).kerning(0.5)
                }
                .frame(maxWidth: .infinity).frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.predktCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(Color.predktAmber.opacity(0.3))
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Ranking Row (Global Rankings section)

fileprivate struct RankingRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let xp: Int
    let isCurrentUser: Bool

    var rankColor: Color {
        if rank == 1 { return Color.predktLime }
        if rank == 2 { return Color(white: 0.72) }
        if rank == 3 { return Color.predktAmber }
        return Color.predktMuted
    }

    var body: some View {
        HStack(spacing: 14) {
            // Rank
            Text("#\(rank)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .leading)

            // Name + streak
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.username.uppercased())
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isCurrentUser ? Color.predktLime : .white)
                        .kerning(0.3)
                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .black)).foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.predktLime).cornerRadius(4)
                    }
                }
                if let streak = entry.current_streak, streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8)).foregroundStyle(Color.predktAmber)
                        Text("\(streak) streak")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.predktAmber)
                    }
                }
            }

            Spacer()

            // XP
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(xp.formatted())")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(isCurrentUser ? Color.predktLime : .white)
                Text("PTS")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.predktMuted).kerning(0.5)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.predktBorder)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(isCurrentUser ? Color.predktLime.opacity(0.05) : Color.clear)
    }
}

// MARK: - League Detail Sheet

struct LeagueDetailView: View {
    let league: League
    @ObservedObject var viewModel: LeagueViewModel
    @Environment(\.dismiss) var dismiss
    @State private var codeCopied = false

    private var entries: [LeaderboardEntry] { viewModel.leagueLeaderboard }

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(league.name.uppercased())
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2)

                        Button(action: {
                            UIPasteboard.general.string = league.invite_code
                            withAnimation(.easeInOut(duration: 0.15)) { codeCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeInOut(duration: 0.15)) { codeCopied = false }
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text("CODE")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(Color.predktMuted).kerning(0.8)
                                Text(league.invite_code)
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color.predktLime)
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(codeCopied ? Color.predktLime : Color.predktMuted)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.predktLime.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.predktLime.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.predktMuted)
                            .padding(9).background(Color.white.opacity(0.07)).cornerRadius(8)
                    }
                }
                .padding(20)
                .background(Color.predktCard)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if entries.count >= 3 {
                            PodiumView(entries: Array(entries.prefix(3)), currentUserId: nil)
                                .padding(.top, 16).padding(.bottom, 4)
                        }
                        VStack(spacing: 6) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                                LeaderboardRow(rank: i + 1, entry: entry, xp: entry.displayXP, isCurrentUser: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, entries.count >= 3 ? 4 : 16)
                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Podium View

struct PodiumView: View {
    let entries: [LeaderboardEntry]
    let currentUserId: String?
    var isWeekly: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if entries.count > 1 {
                PodiumColumn(rank: 2, entry: entries[1],
                             xp: isWeekly ? entries[1].weeklyXP : entries[1].displayXP,
                             height: 88, colour: Color(white: 0.62),
                             isCurrentUser: entries[1].id == currentUserId)
            }
            PodiumColumn(rank: 1, entry: entries[0],
                         xp: isWeekly ? entries[0].weeklyXP : entries[0].displayXP,
                         height: 118, colour: Color.predktLime,
                         isCurrentUser: entries[0].id == currentUserId)
            if entries.count > 2 {
                PodiumColumn(rank: 3, entry: entries[2],
                             xp: isWeekly ? entries[2].weeklyXP : entries[2].displayXP,
                             height: 68, colour: Color.predktAmber,
                             isCurrentUser: entries[2].id == currentUserId)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct PodiumColumn: View {
    let rank: Int; let entry: LeaderboardEntry
    let xp: Int; let height: CGFloat
    let colour: Color; let isCurrentUser: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if rank == 1 {
                    Circle()
                        .stroke(colour.opacity(0.25), lineWidth: pulse ? 6 : 1)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                }
                Circle()
                    .fill(colour.opacity(0.15)).frame(width: 52, height: 52)
                    .overlay(Text(String(entry.username.prefix(1)).uppercased())
                        .font(.system(size: rank == 1 ? 22 : 18, weight: .black)).foregroundStyle(colour))
                    .overlay(Circle().stroke(isCurrentUser ? colour : Color.clear, lineWidth: 2.5))
            }
            .frame(width: 64, height: 64)
            .onAppear { if rank == 1 { pulse = true } }

            Text(entry.username).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)

            if isCurrentUser {
                Text("YOU").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(colour).cornerRadius(4)
            }

            Text("\(xp)").font(.system(size: 12, weight: .black)).foregroundStyle(colour)
            Text("XP").font(.system(size: 9, weight: .bold)).foregroundStyle(colour.opacity(0.55))

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colour.opacity(0.18)).frame(height: height)
                Text("#\(rank)").font(.system(size: 12, weight: .black)).foregroundStyle(colour).padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Leaderboard Row (used in LeagueDetailView)

struct LeaderboardRow: View {
    let rank: Int; let entry: LeaderboardEntry
    let xp: Int; let isCurrentUser: Bool

    var rankColor: Color {
        if rank <= 3  { return Color.predktLime }
        if rank <= 10 { return Color.predktAmber }
        return Color.predktMuted
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.system(size: 13, weight: .black)).foregroundStyle(rankColor).frame(width: 28)
            Circle().fill(rankColor.opacity(0.1)).frame(width: 36, height: 36)
                .overlay(Text(String(entry.username.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .black)).foregroundStyle(rankColor))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.username).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    if isCurrentUser {
                        Text("YOU").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.predktLime).cornerRadius(4)
                    }
                }
                if let streak = entry.current_streak, streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(Color.predktAmber)
                        Text("\(streak) streak").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.predktAmber)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(xp)").font(.system(size: 15, weight: .black))
                    .foregroundStyle(isCurrentUser ? Color.predktLime : .white)
                Text("XP").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktMuted)
            }
        }
        .padding(12)
        .background(isCurrentUser ? Color.predktLime.opacity(0.07) : Color.predktCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isCurrentUser ? Color.predktLime.opacity(0.3) : Color.predktBorder, lineWidth: 1))
    }
}

// MARK: - Create League Sheet

struct CreateLeagueSheet: View {
    @ObservedObject var viewModel: LeagueViewModel
    @Environment(\.dismiss) var dismiss

    private let maxLength = 25
    private let minLength = 3

    // Only letters, numbers, spaces
    private let safePattern = "^[a-zA-Z0-9 ]*$"

    // Sourced from viewModel.bannedWords (local + Supabase remote, synced on launch)

    private let nameSuggestions: [String] = [
        "The Haaland Hurricanes", "Offside Outlaws", "The Messi Mob",
        "Penalty Kings", "Net Busters", "Silk Touch FC",
        "The Pressing Game", "Counter Attack Crew", "Injury Time Heroes",
        "The xG Experts", "Tiki Taka Titans", "Late Night Subs",
        "The Overlap", "Clean Sheet Crew", "Six Yard Box"
    ]

    private var nameStatus: NameStatus {
        let name = viewModel.newLeagueName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return .empty }
        if name.count < minLength { return .tooShort }
        if name.count > maxLength { return .tooLong }
        guard name.range(of: safePattern, options: .regularExpression) != nil else { return .invalidChars }
        if viewModel.bannedWords.contains(where: { name.lowercased().contains($0) }) { return .inappropriate }
        return .safe
    }

    private var canSubmit: Bool { nameStatus == .safe }

    private var borderColor: Color {
        switch nameStatus {
        case .safe:        return Color.predktLime.opacity(0.5)
        case .empty:       return Color.predktBorder
        case .inappropriate, .invalidChars: return Color(red: 1, green: 0.3, blue: 0.3).opacity(0.6)
        case .tooShort, .tooLong:           return Color.predktAmber.opacity(0.5)
        }
    }

    private var statusMessage: String? {
        switch nameStatus {
        case .safe, .empty:    return nil
        case .tooShort:        return "Name must be at least \(minLength) characters"
        case .tooLong:         return "Name must be \(maxLength) characters or fewer"
        case .invalidChars:    return "Only letters, numbers and spaces allowed"
        case .inappropriate:   return "That name isn't allowed — keep it clean"
        }
    }

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Create a Squad")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .padding(.top, 32).padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 8) {
                    // Label row
                    HStack {
                        Text("SQUAD NAME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktMuted).kerning(1)
                        Spacer()
                        Text("\(viewModel.newLeagueName.count)/\(maxLength)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(viewModel.newLeagueName.count > maxLength
                                             ? Color(red: 1, green: 0.3, blue: 0.3)
                                             : Color.predktMuted)
                    }

                    // Text field
                    HStack(spacing: 0) {
                        TextField("e.g. Friday Night Crew", text: $viewModel.newLeagueName)
                            .font(.system(size: 16)).foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.newLeagueName) { _, new in
                                if new.count > maxLength {
                                    viewModel.newLeagueName = String(new.prefix(maxLength))
                                }
                            }

                        // Randomise button
                        Button(action: {
                            viewModel.newLeagueName = nameSuggestions.randomElement() ?? "Penalty Kings"
                        }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.predktLime)
                                .padding(8)
                                .background(Color.predktLime.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(14)
                    .background(Color.predktCard)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1))

                    // Validation message
                    if let msg = statusMessage {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                            Text(msg)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(nameStatus == .inappropriate || nameStatus == .invalidChars
                                         ? Color(red: 1, green: 0.3, blue: 0.3)
                                         : Color.predktAmber)
                        .transition(.opacity)
                    }

                    // Privacy nudge
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.predktMuted)
                        Text("Keep it fun — don't include your real name or contact info")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.predktMuted)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .animation(.easeInOut(duration: 0.15), value: nameStatus == .safe)

                Text("An invite code will be automatically generated for you to share with friends.")
                    .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.top, 16)

                Spacer()

                Button(action: { Task { await viewModel.createLeague() } }) {
                    Text("Create Squad")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(canSubmit ? .black : Color.predktMuted)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(canSubmit ? Color.predktLime : Color.predktCard)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(canSubmit ? Color.clear : Color.predktBorder, lineWidth: 1)
                        )
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 20).padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.2), value: canSubmit)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private enum NameStatus: Equatable {
        case empty, tooShort, tooLong, invalidChars, inappropriate, safe
    }
}

// MARK: - Join League Sheet

struct JoinLeagueSheet: View {
    @ObservedObject var viewModel: LeagueViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Join a Squad")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(.white).padding(.top, 32)
                VStack(alignment: .leading, spacing: 8) {
                    Text("INVITE CODE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
                    TextField("e.g. XK7R4M", text: $viewModel.joinCode)
                        .font(.system(size: 22, weight: .black, design: .monospaced)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(14).background(Color.predktCard).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktLime.opacity(0.3), lineWidth: 1))
                        .autocorrectionDisabled().textInputAutocapitalization(.characters)
                }
                .padding(.horizontal, 20)
                Spacer()
                Button(action: { Task { await viewModel.joinLeague() } }) {
                    Text("Join Squad")
                        .font(.system(size: 16, weight: .black)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color.predktAmber).cornerRadius(16)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
