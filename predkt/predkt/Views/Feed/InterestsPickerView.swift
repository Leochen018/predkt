import SwiftUI

struct InterestsPickerView: View {
    @ObservedObject var viewModel: FeedViewModel
    @Environment(\.dismiss) var dismiss

    // Leagues — kept with flag emojis (flags are not copyrightable)
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
        (40,  "Championship",     "🏴󠁧󠁢󠁥󠁮󠁧󠁿"),
    ]

    // Teams — no logos, just names. GeometricBadge generates the pattern.
    let teams: [(id: Int, name: String)] = [
        (42,  "Arsenal"),
        (50,  "Manchester City"),
        (33,  "Manchester United"),
        (40,  "Liverpool"),
        (47,  "Tottenham"),
        (49,  "Chelsea"),
        (66,  "Aston Villa"),
        (34,  "Newcastle"),
        (65,  "Nottingham Forest"),
        (541, "Real Madrid"),
        (529, "Barcelona"),
        (530, "Atletico Madrid"),
        (489, "AC Milan"),
        (492, "Napoli"),
        (496, "Juventus"),
        (505, "Inter Milan"),
        (157, "Bayern Munich"),
        (165, "Borussia Dortmund"),
        (85,  "PSG"),
        (80,  "Lyon"),
        (81,  "Marseille"),
        (477, "Celtic"),
        (9,   "Ajax"),
        (211, "Benfica"),
        (212, "Porto"),
    ]

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Interests")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                        Text("Personalise your feed and match order")
                            .font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            await viewModel.saveInterests()
                            dismiss()
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.predktLime).cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)

                Divider().background(Color.predktBorder)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // ── LEAGUES ──────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "LEAGUES",
                                count: viewModel.followedLeagueIds.count,
                                subtitle: "Favourite leagues appear first in Play"
                            )

                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 10
                            ) {
                                ForEach(leagues, id: \.id) { league in
                                    LeaguePill(
                                        league: league,
                                        isFollowed: viewModel.followedLeagueIds.contains(league.id),
                                        onTap: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if viewModel.followedLeagueIds.contains(league.id) {
                                                    viewModel.followedLeagueIds.remove(league.id)
                                                } else {
                                                    viewModel.followedLeagueIds.insert(league.id)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // ── TEAMS ─────────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "TEAMS",
                                count: viewModel.followedTeamNames.count,
                                subtitle: "Your team's matches float to the top"
                            )

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ],
                                spacing: 12
                            ) {
                                ForEach(teams, id: \.id) { team in
                                    TeamTile(
                                        team: team,
                                        isFollowed: viewModel.followedTeamNames.contains(team.name),
                                        onTap: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if viewModel.followedTeamNames.contains(team.name) {
                                                    viewModel.followedTeamNames.remove(team.name)
                                                } else {
                                                    viewModel.followedTeamNames.insert(team.name)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let count: Int
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.predktMuted).kerning(1.5)
                if count > 0 {
                    Text("\(count) selected")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.predktLime)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.predktLime.opacity(0.12)).cornerRadius(6)
                }
            }
            Text(subtitle)
                .font(.system(size: 11)).foregroundStyle(Color.predktMuted.opacity(0.7))
        }
    }
}

// MARK: - League Pill

private struct LeaguePill: View {
    let league: (id: Int, name: String, emoji: String)
    let isFollowed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(league.emoji).font(.system(size: 18))

                Text(league.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(
                            isFollowed ? Color.predktLime : Color.predktBorder,
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                    if isFollowed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.predktLime)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                isFollowed
                    ? Color.predktLime.opacity(0.08)
                    : Color.predktCard
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFollowed ? Color.predktLime.opacity(0.4) : Color.predktBorder,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isFollowed ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Team Tile
// Uses GeometricBadge — no external images, no club badges

private struct TeamTile: View {
    let team: (id: Int, name: String)
    let isFollowed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // ✅ Geometric DNA badge — legally safe, no official imagery
                ZStack(alignment: .topTrailing) {
                    GeometricBadge(teamName: team.name)
                        .frame(width: 48, height: 48)
                        .shadow(
                            color: isFollowed ? Color.predktLime.opacity(0.4) : .clear,
                            radius: 8, x: 0, y: 0
                        )

                    if isFollowed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.predktLime)
                            .background(Color.predktBg.clipShape(Circle()))
                            .offset(x: 6, y: -6)
                    }
                }

                // Short display name (2 lines max)
                Text(shortName(team.name))
                    .font(.system(size: 10, weight: isFollowed ? .bold : .medium))
                    .foregroundStyle(isFollowed ? .white : Color.predktMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 6)
            .background(
                isFollowed
                    ? Color.predktLime.opacity(0.08)
                    : Color.predktCard
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isFollowed ? Color.predktLime.opacity(0.4) : Color.predktBorder,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isFollowed ? 1.03 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isFollowed)
    }

    // Shorten long names for the grid
    private func shortName(_ name: String) -> String {
        let overrides: [String: String] = [
            "Manchester City":    "Man City",
            "Manchester United":  "Man United",
            "Tottenham":          "Spurs",
            "Borussia Dortmund":  "Dortmund",
            "Atletico Madrid":    "Atlético",
            "Nottingham Forest":  "Forest",
            "Bayern Munich":      "Bayern",
        ]
        return overrides[name] ?? name
    }
}
