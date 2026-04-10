import SwiftUI

struct InterestsPickerView: View {
    @ObservedObject var viewModel: FeedViewModel
    @Environment(\.dismiss) var dismiss

    let leagues: [(id: Int, name: String, emoji: String)] = [
        (39,  "Premier League",   "🏴󠁧󠁢󠁥󠁮󠁧󠁿"),
        (140, "La Liga",          "🇪🇸"),
        (135, "Serie A",          "🇮🇹"),
        (78,  "Bundesliga",       "🇩🇪"),
        (61,  "Ligue 1",          "🇫🇷"),
        (94,  "Primeira Liga",    "🇵🇹"),
        (88,  "Eredivisie",       "🇳🇱"),
        (2,   "Champions League", "⭐️"),
        (3,   "Europa League",    "🟠"),
    ]

    // Popular teams with their API-Football IDs
    let teams: [(id: Int, name: String, logo: String)] = [
        (42,  "Arsenal",          "https://media.api-sports.io/football/teams/42.png"),
        (50,  "Man City",         "https://media.api-sports.io/football/teams/50.png"),
        (33,  "Man United",       "https://media.api-sports.io/football/teams/33.png"),
        (40,  "Liverpool",        "https://media.api-sports.io/football/teams/40.png"),
        (47,  "Tottenham",        "https://media.api-sports.io/football/teams/47.png"),
        (49,  "Chelsea",          "https://media.api-sports.io/football/teams/49.png"),
        (66,  "Aston Villa",      "https://media.api-sports.io/football/teams/66.png"),
        (541, "Real Madrid",      "https://media.api-sports.io/football/teams/541.png"),
        (529, "Barcelona",        "https://media.api-sports.io/football/teams/529.png"),
        (530, "Atletico Madrid",  "https://media.api-sports.io/football/teams/530.png"),
        (489, "AC Milan",         "https://media.api-sports.io/football/teams/489.png"),
        (492, "Napoli",           "https://media.api-sports.io/football/teams/492.png"),
        (496, "Juventus",         "https://media.api-sports.io/football/teams/496.png"),
        (505, "Inter Milan",      "https://media.api-sports.io/football/teams/505.png"),
        (157, "Bayern Munich",    "https://media.api-sports.io/football/teams/157.png"),
        (165, "Borussia Dortmund","https://media.api-sports.io/football/teams/165.png"),
        (85,  "Paris SG",         "https://media.api-sports.io/football/teams/85.png"),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                // Header
                HStack {
                    Text("Your Interests")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: {
                        Task {
                            await viewModel.saveInterests()
                            dismiss()
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // LEAGUES
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LEAGUES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(leagues, id: \.id) { league in
                                    let isFollowed = viewModel.followedLeagueIds.contains(league.id)
                                    Button(action: {
                                        if isFollowed {
                                            viewModel.followedLeagueIds.remove(league.id)
                                        } else {
                                            viewModel.followedLeagueIds.insert(league.id)
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Text(league.emoji)
                                                .font(.system(size: 16))
                                            Text(league.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            if isFollowed {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                                    .font(.system(size: 14))
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            isFollowed
                                            ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15)
                                            : Color(red: 0.12, green: 0.12, blue: 0.15)
                                        )
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(
                                                    isFollowed
                                                    ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.5)
                                                    : Color.clear,
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        // TEAMS
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEAMS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.6, green: 0.59, blue: 0.68))

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(teams, id: \.id) { team in
                                    let isFollowed = viewModel.followedTeamNames.contains(team.name)
                                    Button(action: {
                                        if isFollowed {
                                            viewModel.followedTeamNames.remove(team.name)
                                        } else {
                                            viewModel.followedTeamNames.insert(team.name)
                                        }
                                    }) {
                                        VStack(spacing: 8) {
                                            ZStack(alignment: .topTrailing) {
                                                AsyncImage(url: URL(string: team.logo)) { phase in
                                                    if case .success(let img) = phase {
                                                        img.resizable().scaledToFit()
                                                    } else {
                                                        Circle()
                                                            .fill(Color.white.opacity(0.07))
                                                    }
                                                }
                                                .frame(width: 40, height: 40)

                                                if isFollowed {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(Color(red: 0.42, green: 0.39, blue: 1.0))
                                                        .font(.system(size: 14))
                                                        .background(Color(red: 0.05, green: 0.05, blue: 0.08))
                                                        .clipShape(Circle())
                                                        .offset(x: 4, y: -4)
                                                }
                                            }

                                            Text(team.name)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(isFollowed ? .white : .gray)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 6)
                                        .background(
                                            isFollowed
                                            ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.15)
                                            : Color(red: 0.12, green: 0.12, blue: 0.15)
                                        )
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    isFollowed
                                                    ? Color(red: 0.42, green: 0.39, blue: 1.0).opacity(0.5)
                                                    : Color.clear,
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
