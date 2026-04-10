import SwiftUI
import Supabase
import Auth

// MARK: - App Colour System (defined once here)
extension Color {
    static let predktBg     = Color(red: 0.031, green: 0.035, blue: 0.055)
    static let predktCard   = Color(red: 0.071, green: 0.078, blue: 0.114)
    static let predktLime   = Color(red: 0.784, green: 1.0,   blue: 0.337)
    static let predktCoral  = Color(red: 1.0,   green: 0.361, blue: 0.361)
    static let predktAmber  = Color(red: 1.0,   green: 0.722, blue: 0.188)
    static let predktMuted  = Color(red: 0.545, green: 0.561, blue: 0.659)
    static let predktBorder = Color.white.opacity(0.07)
}

struct MainTabView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.071, green: 0.078, blue: 0.114, alpha: 1)
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.45, alpha: 1)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("Arena",    systemImage: "flame.fill") }
                .tag(0)

            PredictView()
                .tabItem { Label("Play",     systemImage: "bolt.circle.fill") }
                .tag(1)

            LeagueView()
                .tabItem { Label("Leagues",  systemImage: "trophy.fill") }
                .tag(2)

            ProfileView()
                .tabItem { Label("My Stats", systemImage: "chart.bar.fill") }
                .tag(3)
        }
        .tint(Color.predktLime)
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @StateObject private var feedViewModel = FeedViewModel()

    @State private var isEditingUsername = false
    @State private var editedUsername    = ""
    @State private var isSavingUsername  = false
    @State private var usernameError: String?
    @State private var usernameSaved     = false

    private var displayUsername: String {
        if let n = feedViewModel.userProfile?.username, !n.isEmpty { return n }
        return supabaseManager.user?.email.map { String($0.split(separator: "@").first ?? "Player") } ?? "Player"
    }

    private var xpTotal: Int   { feedViewModel.userProfile?.total_points ?? 0 }
    private var level: Int     { max(1, xpTotal / 500 + 1) }
    private var xpInLevel: Int { xpTotal % 500 }

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("MY STATS")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.predktMuted).kerning(2)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color.predktCard)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // Identity card
                        VStack(spacing: 16) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.predktLime.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Text(String(displayUsername.prefix(1)).uppercased())
                                            .font(.system(size: 32, weight: .black))
                                            .foregroundStyle(Color.predktLime)
                                    )
                                Text("LV\(level)")
                                    .font(.system(size: 10, weight: .black)).foregroundStyle(.black)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.predktLime).cornerRadius(8)
                                    .offset(x: 4, y: 4)
                            }

                            if isEditingUsername {
                                VStack(spacing: 8) {
                                    TextField("Username", text: $editedUsername)
                                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(10).background(Color.white.opacity(0.07)).cornerRadius(8)
                                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                                    if let err = usernameError {
                                        Text(err).font(.system(size: 12)).foregroundStyle(Color.predktCoral)
                                    }
                                    HStack(spacing: 10) {
                                        Button("Cancel") { isEditingUsername = false; usernameError = nil }
                                            .font(.system(size: 13)).foregroundStyle(Color.predktMuted)
                                            .padding(.horizontal, 16).padding(.vertical, 8)
                                            .background(Color.white.opacity(0.05)).cornerRadius(8)
                                        Button(action: saveUsername) {
                                            Text(isSavingUsername ? "Saving…" : "Save")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(Color.predktLime).cornerRadius(8)
                                        .disabled(isSavingUsername)
                                    }
                                }
                            } else {
                                VStack(spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(displayUsername)
                                            .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                                        Button(action: {
                                            editedUsername = displayUsername
                                            usernameError = nil; usernameSaved = false
                                            isEditingUsername = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12)).foregroundStyle(Color.predktLime)
                                                .padding(6).background(Color.predktLime.opacity(0.12)).cornerRadius(6)
                                        }
                                    }
                                    if usernameSaved {
                                        Text("✓ Updated").font(.system(size: 12)).foregroundStyle(Color.predktLime)
                                    }
                                    Text(supabaseManager.user?.email ?? "")
                                        .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                                }
                            }

                            // XP bar
                            VStack(spacing: 6) {
                                HStack {
                                    Text("XP TO LEVEL \(level + 1)")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
                                    Spacer()
                                    Text("\(xpInLevel) / 500")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktLime)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 8)
                                        RoundedRectangle(cornerRadius: 4).fill(Color.predktLime)
                                            .frame(width: geo.size.width * CGFloat(xpInLevel) / 500.0, height: 8)
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                        .padding(20).background(Color.predktCard).cornerRadius(20)

                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            XPStatCard(label: "Total XP",     value: "\(xpTotal)",  icon: "⚡")
                            XPStatCard(label: "This Week",    value: "\(feedViewModel.userProfile?.weekly_points ?? 0)", icon: "📈")
                            XPStatCard(label: "Best Streak",  value: "\(feedViewModel.userProfile?.best_streak ?? 0)🔥",  icon: "🏆")
                            XPStatCard(label: "Daily Streak", value: "\(feedViewModel.userProfile?.daily_streak ?? 0)🔥",  icon: "📅")
                        }

                        Button(action: { Task { try? await supabaseManager.logout() } }) {
                            Text("Log Out")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.predktCoral)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.predktCoral.opacity(0.08)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktCoral.opacity(0.25), lineWidth: 1))
                        }

                        Spacer().frame(height: 40)
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { Task { await feedViewModel.load() } }
    }

    private func saveUsername() {
        let t = editedUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3 else { usernameError = "Must be at least 3 characters."; return }
        isSavingUsername = true; usernameError = nil
        Task {
            do {
                try await supabaseManager.updateUsername(t)
                await feedViewModel.load()
                isEditingUsername = false; usernameSaved = true
            } catch { usernameError = error.localizedDescription }
            isSavingUsername = false
        }
    }
}

struct XPStatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(icon).font(.system(size: 22))
            Text(value).font(.system(size: 24, weight: .black)).foregroundStyle(Color.predktLime)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Color.predktCard).cornerRadius(16)
    }
}
