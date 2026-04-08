import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            TabView(selection: $selectedTab) {
                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "newspaper")
                    }
                    .tag(0)

                PredictView()
                    .tabItem {
                        Label("Predict", systemImage: "plus.circle")
                    }
                    .tag(1)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.circle")
                    }
                    .tag(2)
            }
            .tint(Color(red: 0.42, green: 0.39, blue: 1.0))
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @StateObject private var feedViewModel = FeedViewModel()
    @State private var isLoggingOut = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(16)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // User Info
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text((feedViewModel.userProfile?.username ?? "?").prefix(1).uppercased())
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(Color(red: 0.42, green: 0.39, blue: 1.0))
                                    )

                                VStack(alignment: .leading) {
                                    Text(feedViewModel.userProfile?.username ?? "Loading...")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(feedViewModel.userProfile?.email ?? "")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .cornerRadius(10)

                            // Stats Grid
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    StatCard(
                                        label: "Total Points",
                                        value: String(feedViewModel.userProfile?.total_points ?? 0)
                                    )
                                    StatCard(
                                        label: "Weekly Points",
                                        value: String(feedViewModel.userProfile?.weekly_points ?? 0)
                                    )
                                }
                                HStack(spacing: 12) {
                                    StatCard(
                                        label: "Best Streak",
                                        value: String(feedViewModel.userProfile?.best_streak ?? 0)
                                    )
                                    StatCard(
                                        label: "Daily Streak",
                                        value: String(feedViewModel.userProfile?.daily_streak ?? 0)
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }

                    // Logout Button (OUTSIDE ScrollView)
                    Button(action: {
                        print("🔴 LOG OUT BUTTON TAPPED")
                        isLoggingOut = true

                        Task {
                            print("🚪 Attempting logout...")
                            do {
                                try await supabaseManager.logout()
                                print("✅ Logout successful")
                            } catch {
                                print("❌ Logout failed: \(error)")
                                isLoggingOut = false
                            }
                        }
                    }) {
                        if isLoggingOut {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .red))
                        } else {
                            Text("Log Out")
                                .font(.system(size: 15, weight: .600))
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(12)
                    .disabled(isLoggingOut)
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
        VStack(alignment: .center, spacing: 8) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.42, green: 0.39, blue: 1.0))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.74, green: 0.72, blue: 0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .cornerRadius(10)
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseManager.shared)
}
