import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedTab = 0

    init() {
        // Sets the tab bar background to match your app's theme
        UITabBar.appearance().unselectedItemTintColor = UIColor.gray
        UITabBar.appearance().backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "newspaper.fill")
                }
                .tag(0)

            PredictView()
                .tabItem {
                    Label("Predict", systemImage: "plus.circle.fill")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                .tag(2)
        }
        .tint(Color(red: 0.42, green: 0.39, blue: 1.0))
    }
}

struct ProfileView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @StateObject private var feedViewModel = FeedViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(16)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // User Identity Section
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Text((feedViewModel.userProfile?.username ?? "?").prefix(1).uppercased())
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(feedViewModel.userProfile?.username ?? "Loading...")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(feedViewModel.userProfile?.email ?? "No email linked")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        .cornerRadius(12)

                        // Stats Grid Section
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                StatCard(
                                    label: "Total Points",
                                    value: "\(feedViewModel.userProfile?.total_points ?? 0)"
                                )
                                StatCard(
                                    label: "Weekly Points",
                                    value: "\(feedViewModel.userProfile?.weekly_points ?? 0)"
                                )
                            }
                            HStack(spacing: 12) {
                                StatCard(
                                    label: "Best Streak",
                                    value: "\(feedViewModel.userProfile?.best_streak ?? 0)"
                                )
                                StatCard(
                                    label: "Daily Streak",
                                    value: "\(feedViewModel.userProfile?.daily_streak ?? 0)"
                                )
                            }
                        }

                        Spacer().frame(height: 20)

                        // Action Section
                        Button(action: {
                            Task {
                                try? await supabaseManager.logout()
                            }
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Log Out")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            Task { await feedViewModel.load() }
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))
            
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(12)
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseManager.shared)
}
