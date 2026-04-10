import SwiftUI
import Auth
struct LeagueView: View {
    @StateObject private var viewModel = LeagueViewModel()
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedTab = 0
    let tabs = ["Global", "This Week", "My Leagues"]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEADERBOARD")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Top players")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
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

                if viewModel.isLoading && viewModel.globalLeaderboard.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.predktLime))
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        GlobalLeaderboardTab(
                            entries: viewModel.globalLeaderboard,
                            currentUserId: supabaseManager.user?.id.uuidString.lowercased()
                        ).tag(0)

                        WeeklyLeaderboardTab(
                            entries: viewModel.weeklyLeaderboard,
                            currentUserId: supabaseManager.user?.id.uuidString.lowercased()
                        ).tag(1)

                        MyLeaguesTab(viewModel: viewModel).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .onAppear { Task { await viewModel.load() } }
        .alert("", isPresented: Binding(
            get: { viewModel.actionMessage != nil },
            set: { if !$0 { viewModel.actionMessage = nil } }
        )) {
            Button("OK") { viewModel.actionMessage = nil }
        } message: {
            Text(viewModel.actionMessage ?? "")
        }
    }
}

// MARK: - Global Leaderboard Tab

struct GlobalLeaderboardTab: View {
    let entries: [LeaderboardEntry]
    let currentUserId: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Top 3 podium
                if entries.count >= 3 {
                    PodiumView(entries: Array(entries.prefix(3)), currentUserId: currentUserId)
                        .padding(.top, 16)
                }

                // Rest of list
                VStack(spacing: 6) {
                    ForEach(Array(entries.dropFirst(3).enumerated()), id: \.element.id) { i, entry in
                        LeaderboardRow(
                            rank: i + 4,
                            entry: entry,
                            xp: entry.displayXP,
                            isCurrentUser: entry.id == currentUserId
                        )
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12)

                Spacer().frame(height: 80)
            }
        }
    }
}

// MARK: - Weekly Leaderboard Tab

struct WeeklyLeaderboardTab: View {
    let entries: [LeaderboardEntry]
    let currentUserId: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Weekly reset notice
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(Color.predktAmber)
                    Text("Resets every Monday at midnight")
                        .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                }
                .padding(12)
                .background(Color.predktAmber.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 16).padding(.top, 16)

                if entries.count >= 3 {
                    PodiumView(entries: Array(entries.prefix(3)), currentUserId: currentUserId, isWeekly: true)
                        .padding(.top, 12)
                }

                VStack(spacing: 6) {
                    ForEach(Array(entries.dropFirst(3).enumerated()), id: \.element.id) { i, entry in
                        LeaderboardRow(
                            rank: i + 4,
                            entry: entry,
                            xp: entry.weeklyXP,
                            isCurrentUser: entry.id == currentUserId
                        )
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12)

                Spacer().frame(height: 80)
            }
        }
    }
}

// MARK: - My Leagues Tab

struct MyLeaguesTab: View {
    @ObservedObject var viewModel: LeagueViewModel
    @State private var showingLeagueDetail = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Action buttons
                HStack(spacing: 10) {
                    Button(action: { viewModel.showCreateLeague = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.predktLime)
                            Text("Create League")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.predktLime.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktLime.opacity(0.3), lineWidth: 1))
                    }

                    Button(action: { viewModel.showJoinLeague = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus").foregroundStyle(Color.predktAmber)
                            Text("Join League")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.predktAmber.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktAmber.opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16)

                if viewModel.myLeagues.isEmpty {
                    VStack(spacing: 12) {
                        Text("🏆").font(.system(size: 44))
                        Text("No leagues yet").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                        Text("Create a league or join one with an invite code")
                            .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    }
                    .padding(.top, 60).padding(.horizontal, 40)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.myLeagues) { league in
                            LeagueCard(league: league) {
                                Task {
                                    await viewModel.fetchLeagueLeaderboard(for: league)
                                    showingLeagueDetail = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer().frame(height: 80)
            }
        }
        .sheet(isPresented: $viewModel.showCreateLeague) {
            CreateLeagueSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showJoinLeague) {
            JoinLeagueSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingLeagueDetail) {
            if let league = viewModel.selectedLeague {
                LeagueDetailView(league: league, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Podium View

struct PodiumView: View {
    let entries: [LeaderboardEntry]
    let currentUserId: String?
    var isWeekly: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 2nd
            if entries.count > 1 {
                PodiumColumn(rank: 2, entry: entries[1], xp: isWeekly ? entries[1].weeklyXP : entries[1].displayXP,
                             height: 90, colour: Color.predktMuted, isCurrentUser: entries[1].id == currentUserId)
            }
            // 1st
            PodiumColumn(rank: 1, entry: entries[0], xp: isWeekly ? entries[0].weeklyXP : entries[0].displayXP,
                         height: 120, colour: Color.predktLime, isCurrentUser: entries[0].id == currentUserId)
            // 3rd
            if entries.count > 2 {
                PodiumColumn(rank: 3, entry: entries[2], xp: isWeekly ? entries[2].weeklyXP : entries[2].displayXP,
                             height: 70, colour: Color.predktAmber, isCurrentUser: entries[2].id == currentUserId)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct PodiumColumn: View {
    let rank: Int
    let entry: LeaderboardEntry
    let xp: Int
    let height: CGFloat
    let colour: Color
    let isCurrentUser: Bool

    var rankEmoji: String { rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉" }

    var body: some View {
        VStack(spacing: 8) {
            Text(rankEmoji).font(.system(size: 24))

            Circle()
                .fill(colour.opacity(0.2))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(String(entry.username.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .black)).foregroundStyle(colour)
                )
                .overlay(
                    Circle().stroke(isCurrentUser ? colour : Color.clear, lineWidth: 2)
                )

            Text(entry.username)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)

            Text("\(xp) XP")
                .font(.system(size: 10, weight: .black)).foregroundStyle(colour)

            Rectangle()
                .fill(colour.opacity(0.25))
                .frame(height: height)
                .overlay(
                    Text("#\(rank)").font(.system(size: 13, weight: .black)).foregroundStyle(colour)
                )
                .cornerRadius(8, corners: [.topLeft, .topRight])
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Leaderboard Row

struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let xp: Int
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.predktMuted)
                .frame(width: 28)

            Circle()
                .fill(Color.predktLime.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(entry.username.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktLime)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.username)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                if let streak = entry.current_streak, streak > 0 {
                    Text("🔥 \(streak) streak")
                        .font(.system(size: 10)).foregroundStyle(Color.predktAmber)
                }
            }

            Spacer()

            Text("\(xp) XP")
                .font(.system(size: 14, weight: .black)).foregroundStyle(Color.predktLime)
        }
        .padding(12)
        .background(isCurrentUser ? Color.predktLime.opacity(0.08) : Color.predktCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentUser ? Color.predktLime.opacity(0.3) : Color.predktBorder, lineWidth: 1)
        )
    }
}

// MARK: - League Card

struct LeagueCard: View {
    let league: League
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.predktAmber.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(Text("🏆").font(.system(size: 20)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(league.name)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text("Code: \(league.invite_code)")
                        .font(.system(size: 11)).foregroundStyle(Color.predktMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.predktMuted).font(.system(size: 13))
            }
            .padding(14)
            .background(Color.predktCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.predktBorder, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - League Detail Sheet

struct LeagueDetailView: View {
    let league: League
    @ObservedObject var viewModel: LeagueViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(league.name.uppercased())
                            .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktMuted).kerning(2)
                        HStack(spacing: 6) {
                            Text("Invite code:")
                                .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                            Text(league.invite_code)
                                .font(.system(size: 12, weight: .black)).foregroundStyle(Color.predktLime)
                        }
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.predktMuted)
                            .padding(8).background(Color.white.opacity(0.07)).cornerRadius(8)
                    }
                }
                .padding(20)
                .background(Color.predktCard)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(Array(viewModel.leagueLeaderboard.enumerated()), id: \.element.id) { i, entry in
                            LeaderboardRow(rank: i + 1, entry: entry, xp: entry.displayXP, isCurrentUser: false)
                        }
                        Spacer().frame(height: 40)
                    }
                    .padding(16)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Create League Sheet

struct CreateLeagueSheet: View {
    @ObservedObject var viewModel: LeagueViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Create a League")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .padding(.top, 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LEAGUE NAME").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
                    TextField("e.g. Friday Night Crew", text: $viewModel.newLeagueName)
                        .font(.system(size: 16)).foregroundStyle(.white)
                        .padding(14).background(Color.predktCard).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktBorder, lineWidth: 1))
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 20)

                Text("An invite code will be automatically generated for you to share with friends.")
                    .font(.system(size: 13)).foregroundStyle(Color.predktMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)

                Spacer()

                Button(action: { Task { await viewModel.createLeague() } }) {
                    Text("Create League")
                        .font(.system(size: 16, weight: .black)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color.predktLime).cornerRadius(16)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
                Text("Join a League")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .padding(.top, 32)

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
                    Text("Join League")
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
