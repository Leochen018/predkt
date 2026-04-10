import SwiftUI
import Supabase
import Auth

struct MainTabView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor.gray
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "newspaper.fill") }
                .tag(0)

            PredictView()
                .tabItem { Label("Predict", systemImage: "plus.circle.fill") }
                .tag(1)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
                .tag(2)
        }
        .tint(Color(red: 0.42, green: 0.39, blue: 1.0))
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @StateObject private var feedViewModel = FeedViewModel()

    @State private var isEditingUsername = false
    @State private var editedUsername = ""
    @State private var isSavingUsername = false
    @State private var usernameError: String?
    @State private var usernameSaved = false

    // The username to display — prefer profile data, fall back to auth metadata, then email prefix
    private var displayUsername: String {
        if let name = feedViewModel.userProfile?.username, !name.isEmpty {
            return name
        }
        if let metaName = supabaseManager.user?.userMetadata["username"]?.stringValue,
           !metaName.isEmpty {
            return metaName
        }
        return supabaseManager.user?.email.map { String($0.split(separator: "@").first ?? "User") } ?? "User"
    }

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

                        // MARK: Identity Card
                        VStack(spacing: 16) {
                            // Avatar
                            Circle()
                                .fill(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Text(String(displayUsername.prefix(1)).uppercased())
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                )

                            // Username row
                            if isEditingUsername {
                                VStack(spacing: 8) {
                                    TextField("Username", text: $editedUsername)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.07))
                                        .cornerRadius(8)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)

                                    if let err = usernameError {
                                        Text(err)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.red)
                                    }

                                    HStack(spacing: 12) {
                                        Button("Cancel") {
                                            isEditingUsername = false
                                            usernameError = nil
                                        }
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.gray)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(8)

                                        Button(action: saveUsername) {
                                            if isSavingUsername {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                            } else {
                                                Text("Save")
                                                    .font(.system(size: 14, weight: .semibold))
                                            }
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                                        .cornerRadius(8)
                                        .disabled(isSavingUsername)
                                    }
                                }
                            } else {
                                VStack(spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(displayUsername)
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(.white)

                                        Button(action: {
                                            editedUsername = displayUsername
                                            usernameError = nil
                                            usernameSaved = false
                                            isEditingUsername = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                                .padding(6)
                                                .background(Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15))
                                                .cornerRadius(6)
                                        }
                                    }

                                    if usernameSaved {
                                        Text("✓ Username updated")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.green)
                                    }

                                    Text(supabaseManager.user?.email ?? "")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        .cornerRadius(12)

                        // MARK: Stats Grid
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                StatCard(label: "Total Points",  value: "\(feedViewModel.userProfile?.total_points ?? 0)")
                                StatCard(label: "Weekly Points", value: "\(feedViewModel.userProfile?.weekly_points ?? 0)")
                            }
                            HStack(spacing: 12) {
                                StatCard(label: "Best Streak",  value: "\(feedViewModel.userProfile?.best_streak ?? 0)")
                                StatCard(label: "Daily Streak", value: "\(feedViewModel.userProfile?.daily_streak ?? 0)")
                            }
                        }

                        Spacer().frame(height: 8)

                        // MARK: Log Out
                        Button(action: {
                            Task { try? await supabaseManager.logout() }
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

    // MARK: - Save Username

    private func saveUsername() {
        let trimmed = editedUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            usernameError = "Username can't be empty."
            return
        }
        guard trimmed.count >= 3 else {
            usernameError = "Must be at least 3 characters."
            return
        }

        isSavingUsername = true
        usernameError = nil

        Task {
            do {
                try await supabaseManager.updateUsername(trimmed)
                await feedViewModel.load() // reload profile so displayUsername updates
                isEditingUsername = false
                usernameSaved = true
            } catch {
                usernameError = error.localizedDescription
            }
            isSavingUsername = false
        }
    }
}

// MARK: - Stat Card

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
