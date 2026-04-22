import SwiftUI
import Supabase

// MARK: - PredictView

struct PredictView: View {
    @StateObject private var viewModel = PredictViewModel()
    @State private var showingQuestions = false
    @State private var selectedMatch: Match?
    @State private var myPicksCount = 0
    @State private var showingLimitAlert = false

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                carouselView
                contentView
            }
        }
        .onAppear {
            Task {
                await viewModel.loadMatches()
                if let picks = try? await SupabaseManager.shared.fetchMyPicks() {
                    let todayStart = Calendar.current.startOfDay(for: Date())
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                    f.timeZone = TimeZone(identifier: "UTC")
                    f.locale = Locale(identifier: "en_US_POSIX")
                    let todayPicks = picks.filter {
                        guard let d = f.date(from: $0.created_at) else { return false }
                        return Calendar.current.startOfDay(for: d) == todayStart
                    }
                    myPicksCount = Set(todayPicks.map { $0.match }).count
                    viewModel.predictedTodayMatches = Set(todayPicks.map { $0.match })
                }
            }
        }
        .alert("Daily limit reached 🎯", isPresented: $showingLimitAlert) {
            Button("View My Picks") {
                NotificationCenter.default.post(name: Notification.Name("predkt.switchTab"), object: 0)
                NotificationCenter.default.post(name: Notification.Name("predkt.switchFeedTab"), object: 1)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You've predicted on 5 matches today — that's your limit!\n\nRemove a prediction in My Picks to free up a slot.")
        }
        .sheet(isPresented: $showingQuestions) {
            if let match = selectedMatch {
                QuestionsSheetView(
                    match: match,
                    viewModel: viewModel,
                    myPicksCount: myPicksCount,
                    isPresented: $showingQuestions,
                    onSubmit: {
                        if let match = selectedMatch {
                            viewModel.predictedTodayMatches.insert(match.displayName)
                            myPicksCount = viewModel.predictedTodayMatches.count
                        }
                        Task {
                            if let picks = try? await SupabaseManager.shared.fetchMyPicks() {
                                let todayStart = Calendar.current.startOfDay(for: Date())
                                let f = DateFormatter()
                                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                                f.timeZone = TimeZone(identifier: "UTC")
                                f.locale = Locale(identifier: "en_US_POSIX")
                                let todayPicks = picks.filter {
                                    guard let d = f.date(from: $0.created_at) else { return false }
                                    return Calendar.current.startOfDay(for: d) == todayStart
                                }
                                myPicksCount = Set(todayPicks.map { $0.match }).count
                                viewModel.predictedTodayMatches = Set(todayPicks.map { $0.match })
                            }
                        }
                    }
                )
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLAY")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.predktMuted).kerning(2)
                Text("Pick your winners")
                    .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
            }
            Spacer()
            if !viewModel.isLoading {
                Button(action: { Task { await viewModel.refreshMatches() } }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.predktMuted).font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var carouselView: some View {
        DateCarousel(
            selectedDate: viewModel.selectedDate,
            datesWithMatches: viewModel.datesWithMatches,
            matchesLoaded: !viewModel.matches.isEmpty,
            onSelect: { date in
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectedDate = date }
                viewModel.scheduleRegroupPublic()
            }
        )
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.matches.isEmpty {
            SkeletonMatchList()
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Spacer()
                Text("⚠️").font(.system(size: 40))
                Text(error).foregroundStyle(Color.predktCoral)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
                Button(action: { Task { await viewModel.refreshMatches() } }) {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Color.predktLime).cornerRadius(12)
                }
                Spacer()
            }
        } else {
            MatchListView(
                groups: viewModel.groupedMatchesForDate,
                filteredCount: viewModel.filteredCount,
                hasFavourites: !viewModel.favouriteLeagueIds.isEmpty || !viewModel.favouriteTeamNames.isEmpty,
                isFavouriteMatch: { viewModel.isFavouriteMatch($0) },
                onSelect: { match in
                    let isNewMatch = !viewModel.predictedTodayMatches.contains(match.displayName)
                    if isNewMatch && viewModel.predictedTodayMatches.count >= 5 {
                        selectedMatch = match
                        showingLimitAlert = true
                        return
                    }
                    viewModel.clearAnswers()
                    selectedMatch = match
                    showingQuestions = true
                },
                onNextDay:    { viewModel.goToNextDay() },
                onSwipeLeft:  { viewModel.goToNextDay() },
                onSwipeRight: { viewModel.goToPreviousDay() }
            )
        }
    }
}

// MARK: - DateCarousel

private struct DateCarousel: View {
    let selectedDate: Date
    let datesWithMatches: Set<String>
    let matchesLoaded: Bool
    let onSelect: (Date) -> Void

    private static let localFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<22, id: \.self) { i in
                        let date = Calendar.current.date(byAdding: .day, value: i - 7,
                            to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        let hasMatches = matchesLoaded && datesWithMatches.contains(Self.localFmt.string(from: date))
                        GameDateChip(date: date, isSelected: isSelected, hasMatches: hasMatches,
                            action: { onSelect(date) }).id(i)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .onChange(of: selectedDate) {
                let today = Calendar.current.startOfDay(for: Date())
                let days = Calendar.current.dateComponents([.day], from: today, to: selectedDate).day ?? 0
                let index = max(0, min(days + 7, 21))
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .background(Color.predktCard.opacity(0.5))
    }
}

// MARK: - MatchListView

private struct MatchListView: View {
    let groups: [(league: String, matches: [Match], isFavourite: Bool)]
    let filteredCount: Int
    let hasFavourites: Bool
    let isFavouriteMatch: (Match) -> Bool
    let onSelect: (Match) -> Void
    let onNextDay: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    var body: some View {
        Group {
            if groups.isEmpty { EmptyMatchesCard(onNext: onNextDay) } else { matchList }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    let h = value.translation.width
                    let v = abs(value.translation.height)
                    guard abs(h) > v * 1.5 else { return }
                    if h < -40 { onSwipeLeft() } else { onSwipeRight() }
                }
        )
    }

    private var matchList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(filteredCount) MATCHES · \(groups.count) COMPETITIONS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.predktMuted).kerning(1)
                    Spacer()
                    if hasFavourites {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.predktAmber)
                            Text("FAVES FIRST").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.predktAmber)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                ForEach(groups, id: \.league) { group in
                    LeagueSection(league: group.league, matches: group.matches,
                        isFavourite: group.isFavourite, isFavouriteMatch: isFavouriteMatch, onSelect: onSelect)
                }
                Color.clear.frame(height: 80)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - LeagueSection

private struct LeagueSection: View {
    let league: String
    let matches: [Match]
    let isFavourite: Bool
    let isFavouriteMatch: (Match) -> Bool
    let onSelect: (Match) -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 10) {
                    Rectangle().fill(isFavourite ? Color.predktAmber : Color.predktLime)
                        .frame(width: 3, height: 16).cornerRadius(2)
                    if isFavourite {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.predktAmber)
                    }
                    Text(league.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(isFavourite ? Color.predktAmber : .white).kerning(0.5)
                    Spacer()
                    Text("\(matches.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isFavourite ? Color.predktAmber : Color.predktLime)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((isFavourite ? Color.predktAmber : Color.predktLime).opacity(0.12))
                        .cornerRadius(6)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktMuted)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.predktCard.opacity(isFavourite ? 0.7 : 0.5))
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.id) { match in
                        MatchRowButton(match: match, isFavourite: isFavouriteMatch(match), onTap: { onSelect(match) })
                        if match.id != matches.last?.id {
                            Divider().background(Color.predktBorder).padding(.leading, 70)
                        }
                    }
                }
                .background(Color.predktBg)
            }
            Divider().background(Color.predktBorder)
        }
    }
}

// MARK: - MatchRowButton

private struct MatchRowButton: View, Equatable {
    let match: Match
    let isFavourite: Bool
    let onTap: () -> Void

    static func == (lhs: MatchRowButton, rhs: MatchRowButton) -> Bool {
        lhs.match.id == rhs.match.id && lhs.match.status == rhs.match.status &&
        lhs.match.homeGoals == rhs.match.homeGoals && lhs.match.awayGoals == rhs.match.awayGoals &&
        lhs.isFavourite == rhs.isFavourite
    }

    var body: some View {
        Button(action: onTap) { MatchRowContent(match: match, isFavourite: isFavourite) }
            .buttonStyle(PlainButtonStyle())
    }
}

private struct MatchRowContent: View {
    let match: Match
    let isFavourite: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                if match.isLive {
                    Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                    Text(match.elapsed.map { "\($0)'" } ?? "LIVE")
                        .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                } else if match.isFinished {
                    Text("FT").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktMuted)
                } else {
                    Text(match.kickoffTime)
                        .font(.system(size: 15, weight: .black)).foregroundStyle(Color.predktLime)
                    Text("KO").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.6))
                }
            }
            .frame(width: 60)

            Rectangle().fill(Color.predktBorder).frame(width: 1, height: 60)

            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    TeamBadgeView(url: match.homeLogo, teamName: match.home).frame(width: 28, height: 28)
                    Text(match.home).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if match.isLive || match.isFinished {
                        VStack(spacing: 2) {
                            Text(match.score).font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                            if match.isLive {
                                Text("LIVE").font(.system(size: 7, weight: .black)).foregroundStyle(Color.predktCoral)
                            }
                        }
                    } else {
                        Text("vs").font(.system(size: 12)).foregroundStyle(Color.predktMuted)
                    }
                }
                .frame(width: 60)

                HStack(spacing: 10) {
                    Text(match.away).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).multilineTextAlignment(.trailing)
                    TeamBadgeView(url: match.awayLogo, teamName: match.away).frame(width: 28, height: 28)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            if isFavourite {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color.predktAmber).frame(width: 28)
            }
        }
        .frame(height: 72)
        .background(isFavourite ? Color.predktAmber.opacity(0.04) : Color.predktBg)
        .contentShape(Rectangle())
    }
}

// MARK: - Skeleton Loading

struct SkeletonMatchList: View {
    @State private var shimmer = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in SkeletonLeagueSection(shimmer: shimmer) }
            }.padding(.top, 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}

private struct SkeletonLeagueSection: View {
    let shimmer: Bool
    private var c: Color { Color.white.opacity(shimmer ? 0.08 : 0.04) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Rectangle().fill(Color.predktLime.opacity(0.3)).frame(width: 3, height: 16).cornerRadius(2)
                RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 120, height: 11)
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(c).frame(width: 24, height: 22)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Color.predktCard.opacity(0.5))
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 28, height: 14).frame(width: 60)
                    Rectangle().fill(Color.predktBorder).frame(width: 1, height: 60)
                    HStack {
                        HStack(spacing: 10) {
                            Circle().fill(c).frame(width: 28, height: 28)
                            RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 70, height: 11)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 20, height: 11).frame(width: 60)
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 70, height: 11)
                            Circle().fill(c).frame(width: 28, height: 28)
                        }.frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(.horizontal, 16)
                }
                .frame(height: 72).background(Color.predktBg)
                Divider().background(Color.predktBorder).padding(.leading, 70)
            }
            Divider().background(Color.predktBorder)
        }
    }
}

// MARK: - Question Group  (bundles related questions onto one swipeable page)

fileprivate struct QuestionGroup: Identifiable {
    let id = UUID()
    let title: String
    let questions: [PredictViewModel.Question]
}

// MARK: - Questions Sheet  ★ REDESIGNED ★
// Swipe horizontally between prediction categories.
// No poll bars or probability percentages — just clean tiles and XP.

struct QuestionsSheetView: View {
    let match: Match
    @ObservedObject var viewModel: PredictViewModel
    let myPicksCount: Int
    @Binding var isPresented: Bool
    let onSubmit: () -> Void

    @State private var groups: [QuestionGroup] = []
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                matchHeader
                if viewModel.isLoadingOdds {
                    QuestionsSkeleton()
                } else if groups.isEmpty {
                    VStack {
                        Spacer()
                        Text("No predictions available yet")
                            .font(.system(size: 15)).foregroundStyle(Color.predktMuted)
                        Spacer()
                    }
                } else {
                    categoryPillNav
                    TabView(selection: $currentIndex) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                            GroupedQuestionPageView(group: group, viewModel: viewModel, isLive: match.isLive)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            if !viewModel.lockedAnswers.isEmpty { submitBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadOdds(for: match)
            groups = buildGroups(from: viewModel.getQuestions(for: match))
        }
    }

    // ── Category pill nav ────────────────────────────────────────────────────

    private var categoryPillNav: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { currentIndex = idx }
                        } label: {
                            Text(group.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(currentIndex == idx ? .black : Color.predktMuted)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(currentIndex == idx ? Color.predktLime : Color.predktCard)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20)
                                    .stroke(currentIndex == idx ? .clear : Color.predktBorder, lineWidth: 1))
                        }
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .onChange(of: currentIndex) { _, idx in
                withAnimation { proxy.scrollTo(idx, anchor: .center) }
            }
        }
        .background(Color.predktCard.opacity(0.45))
    }

    // ── Group builder ─────────────────────────────────────────────────────────

    private func buildGroups(from qs: [PredictViewModel.Question]) -> [QuestionGroup] {
        func family(_ category: String) -> (key: String, title: String) {
            let c = category.lowercased()
            // Player scorer props — always moved to first position
            if c.contains("anytime goalscorer") || c.contains("first goalscorer") ||
               c.contains("last goalscorer")    || c.contains("score 2+") ||
               c.contains("hat-trick") {
                return ("scorers", "Scorers")
            }
            // Corners (full match + HT merged)
            if c.contains("corners") {
                return ("corners", "Corners")
            }
            // BTTS all variants
            if c.contains("btts") || c.contains("both teams to score") || c.contains("score in both") {
                return ("btts", "BTTS")
            }
            // Full-time result + variants
            if c.contains("full-time result") || c.contains("double chance") || c.contains("draw no bet") {
                return ("result", "Result")
            }
            // Handicap
            if c.contains("asian handicap") || c.contains("handicap") {
                return ("handicap", "Handicap")
            }
            // Goals O/U (whole-match only)
            if c.contains("over/under") || c.contains("exact number") ||
               (c.contains("odd or even") && !c.contains("home") && !c.contains("away") && !c.contains("player")) {
                return ("goals", "Goals O/U")
            }
            // Half-time markets (checked BEFORE scores so HT correct scores land here, not in scores)
            if c.contains("first half")  || c.contains("second half") ||
               c.contains("half-time")   || c.contains("half time")   ||
               c.contains("ht/ft") {
                return ("halftime", "Half-Time")
            }
            // Scores — full-time correct score, winning margin, win to nil, clean sheet
            if c.contains("correct score") || c.contains("winning margin") ||
               c.contains("win to nil")    || c.contains("clean sheet") {
                return ("scores", "Scores")
            }
            // Team goals
            if (c.contains("goals") && (c.contains("home") || c.contains("away"))) ||
               c.contains("first team to score") || c.contains("last team to score") {
                return ("teamgoals", "Team Goals")
            }
            // Cards — total O/U AND player bookings in one section
            if (c.contains("booking") || c.contains("card")) {
                return ("cards", "Cards")
            }
            // Shots (whole-match)
            if c.contains("shots") && !c.contains("player") {
                return ("shots", "Shots")
            }
            // Remaining player props
            if c.contains("assist") || c.contains("booked") ||
               c.contains("shots on target") || c.contains("fouled") {
                return ("playerprops", "Player Props")
            }
            return ("_\(category)", String(category.prefix(14)))
        }

        var buckets: [String: (title: String, questions: [PredictViewModel.Question])] = [:]
        var order: [String] = []

        for q in qs {
            let (key, title) = family(q.category)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title: title, questions: [q])
            } else {
                buckets[key]!.questions.append(q)
            }
        }

        if let idx = order.firstIndex(of: "scorers"), idx != 0 {
            order.remove(at: idx)
            order.insert("scorers", at: 0)
        }

        return order.compactMap { key in
            guard let b = buckets[key] else { return nil }
            return QuestionGroup(title: b.title, questions: b.questions)
        }
    }

    // ── Match header ─────────────────────────────────────────────────────────

    private var matchHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                        .padding(8).background(Color.white.opacity(0.07)).cornerRadius(8)
                }
                Spacer()
                // Progress indicator
                if !groups.isEmpty {
                    Text("\(currentIndex + 1) / \(groups.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                }
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.predktCoral.opacity(0.1)).cornerRadius(6)
                } else {
                    // Balance the layout
                    Color.clear.frame(width: 44, height: 1)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            // Teams row
            HStack(alignment: .center, spacing: 0) {
                // Home team
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.homeLogo, teamName: match.home).frame(width: 44, height: 44)
                    Text(match.home)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // Score / vs / time
                VStack(spacing: 4) {
                    if match.isLive || match.isFinished {
                        Text(match.score)
                            .font(.system(size: 26, weight: .black)).foregroundStyle(.white)
                    } else {
                        Text("vs")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.predktMuted)
                        Text(match.kickoffTime)
                            .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktLime)
                    }
                    Text(match.competition)
                        .font(.system(size: 10)).foregroundStyle(Color.predktMuted)
                        .lineLimit(1)
                }
                .frame(width: 100)

                // Away team
                VStack(spacing: 6) {
                    TeamBadgeView(url: match.awayLogo, teamName: match.away).frame(width: 44, height: 44)
                    Text(match.away)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)

            if match.isLive {
                HStack(spacing: 5) {
                    Circle().fill(Color.predktCoral).frame(width: 4, height: 4)
                    Text("Late entry — XP is reduced for live picks")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.predktCoral.opacity(0.8))
                }
                .padding(.bottom, 10)
            }

            Divider().background(Color.predktBorder)
        }
        .background(Color.predktCard)
    }

    // ── Submit bar ───────────────────────────────────────────────────────────

    private var submitBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.predktBg.opacity(0), Color.predktBg],
                startPoint: .top, endPoint: .bottom).frame(height: 22)
            Button {
                Task {
                    let ok = await viewModel.submitPlays(match: match, myPicksCount: myPicksCount)
                    if ok { isPresented = false; onSubmit() }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isCombo ? "\(viewModel.lockedAnswers.count)-PICK COMBO" : "LOCK IN PLAY")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(.black.opacity(0.55)).kerning(1)
                        Text(viewModel.lockedAnswers.map { $0.shortLabel }.joined(separator: "  +  "))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.black).lineLimit(1)
                    }
                    Spacer()
                    if viewModel.isSubmitting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        HStack(spacing: 3) {
                            Text("+\(viewModel.totalXP)")
                                .font(.system(size: 22, weight: .black)).foregroundStyle(.black)
                            Text("XP")
                                .font(.system(size: 13, weight: .black)).foregroundStyle(.black.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 24).frame(height: 62).background(Color.predktLime)
            }
            .disabled(viewModel.isSubmitting)
        }
    }
}

// MARK: - Question Page

struct QuestionPageView: View {
    let question: PredictViewModel.Question
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Prompt
                Text(question.prompt)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
                    .padding(.bottom, 28)

                // Answer layout — tiles for ≤3, rows for >3
                if question.answers.count <= 3 {
                    tileGrid
                } else {
                    rowList
                }

                // Swipe hint
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.predktMuted.opacity(0.35))
                    Text("swipe to explore categories")
                        .font(.system(size: 11)).foregroundStyle(Color.predktMuted.opacity(0.35))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.predktMuted.opacity(0.35))
                }
                .padding(.top, 24)

                Color.clear.frame(height: viewModel.lockedAnswers.isEmpty ? 40 : 110)
            }
        }
    }

    // 2 answers → 2 columns, 3 answers → 3 columns
    private var tileGrid: some View {
        let cols: [GridItem] = question.answers.count == 2
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(question.answers) { answer in
                AnswerTileView(answer: answer, viewModel: viewModel, isLive: isLive)
            }
        }
        .padding(.horizontal, 20)
    }

    // 4+ answers → vertical list
    private var rowList: some View {
        VStack(spacing: 8) {
            ForEach(question.answers) { answer in
                AnswerRowView(answer: answer, viewModel: viewModel, isLive: isLive)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Grouped Question Page

fileprivate struct GroupedQuestionPageView: View {
    let group: QuestionGroup
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false

    @State private var showMaxToast = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if group.questions.count == 1 {
                        singleQuestionBlock(group.questions[0], isSolo: true)
                    } else {
                        Text(group.title)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 28)
                            .padding(.bottom, 6)

                        Text("Pick one from each")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.predktMuted.opacity(0.6))
                            .padding(.bottom, 20)

                        ForEach(Array(group.questions.enumerated()), id: \.offset) { idx, q in
                            if idx > 0 {
                                Divider()
                                    .background(Color.predktBorder)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 20)
                            }
                            singleQuestionBlock(q, isSolo: false)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.predktMuted.opacity(0.35))
                        Text("swipe to explore categories")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.predktMuted.opacity(0.35))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.predktMuted.opacity(0.35))
                    }
                    .padding(.top, 24)

                    Color.clear.frame(height: viewModel.lockedAnswers.isEmpty ? 40 : 110)
                }
            }

            // Max-players toast
            if showMaxToast {
                Text("Max 2 players")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.predktLime)
                    .cornerRadius(20)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showMaxToast)
    }

    @ViewBuilder
    private func singleQuestionBlock(_ q: PredictViewModel.Question, isSolo: Bool) -> some View {
        VStack(spacing: 0) {
            Text(q.prompt)
                .font(.system(size: isSolo ? 24 : 18, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, isSolo ? 32 : 0)
                .padding(.bottom, 22)

            if isPlayerQuestion(q) {
                playerGrid(q)
            } else if isCorrectScore(q) {
                correctScoreGrid(q)
            } else if q.answers.count <= 3 {
                tileGrid(q)
            } else {
                rowList(q)
            }
        }
    }

    // True when the question is a player name list (uses 2-column chip grid)
    private static let allPlayerPrefixes = ["any_", "first_", "last_", "score2_", "hattrick_",
                                            "card_", "assist_", "sot_", "fouled_"]
    private func isPlayerQuestion(_ q: PredictViewModel.Question) -> Bool {
        guard let first = q.answers.first else { return false }
        return Self.allPlayerPrefixes.contains { first.group.hasPrefix($0) }
    }

    // True when the question is a correct-score market (uses compact score grid)
    private func isCorrectScore(_ q: PredictViewModel.Question) -> Bool {
        q.category.lowercased().contains("correct score")
    }

    // 2-column grid for player selection
    private func playerGrid(_ q: PredictViewModel.Question) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(q.answers) { answer in
                PlayerSelectChip(
                    answer: answer,
                    viewModel: viewModel,
                    isLive: isLive,
                    onMaxReached: {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        showMaxToast = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            showMaxToast = false
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }

    // Compact 3-column grid for correct score markets
    private func correctScoreGrid(_ q: PredictViewModel.Question) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(q.answers) { answer in
                ScoreChipView(answer: answer, viewModel: viewModel, isLive: isLive)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tileGrid(_ q: PredictViewModel.Question) -> some View {
        let cols: [GridItem] = q.answers.count == 2
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(q.answers) { answer in
                AnswerTileView(answer: answer, viewModel: viewModel, isLive: isLive)
            }
        }
        .padding(.horizontal, 20)
    }

    private func rowList(_ q: PredictViewModel.Question) -> some View {
        VStack(spacing: 8) {
            ForEach(q.answers) { answer in
                AnswerRowView(answer: answer, viewModel: viewModel, isLive: isLive)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Answer Tile  (used for ≤3 options — big, game-like)

struct AnswerTileView: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false

    var isLocked:     Bool { viewModel.isLocked(answer) }
    var isConflicted: Bool { viewModel.conflicts(answer) }
    var xp: Int { isLive ? answer.liveXpValue() : answer.xpValue }

    var body: some View {
        Button {
            guard !isConflicted else { return }
            viewModel.lockAnswer(answer)
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 8)

                // Short label — big and bold
                Text(answer.shortLabel)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(isLocked ? .black : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)

                // Full label if it differs from shortLabel
                if answer.label != answer.shortLabel {
                    Text(answer.label)
                        .font(.system(size: 10))
                        .foregroundStyle(isLocked ? .black.opacity(0.5) : Color.predktMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                // Projected likelihood
                Text("\(answer.probability)% likely")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isLocked ? .black.opacity(0.45) : Color.predktMuted)

                // XP badge
                Text("+\(xp) XP")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isLocked ? .black : Color.predktLime)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((isLocked ? Color.black : Color.predktLime).opacity(0.13))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 10).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(isLocked ? Color.predktLime : Color.predktCard)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(isLocked ? .clear : Color.predktBorder, lineWidth: 1))
            .opacity(isConflicted ? 0.22 : 1.0)
            .scaleEffect(isLocked ? 1.03 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isLocked)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicted)
    }
}

// MARK: - Answer Row  (used for 4+ options — compact list)

struct AnswerRowView: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false

    var isLocked:     Bool { viewModel.isLocked(answer) }
    var isConflicted: Bool { viewModel.conflicts(answer) }
    var xp: Int { isLive ? answer.liveXpValue() : answer.xpValue }

    var body: some View {
        Button {
            guard !isConflicted else { return }
            viewModel.lockAnswer(answer)
        } label: {
            HStack(spacing: 14) {
                // Selection circle
                ZStack {
                    Circle()
                        .stroke(isLocked ? Color.predktLime : Color.white.opacity(0.15), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isLocked { Circle().fill(Color.predktLime).frame(width: 13, height: 13) }
                }

                Text(answer.label)
                    .font(.system(size: 14, weight: isLocked ? .semibold : .regular))
                    .foregroundStyle(isConflicted ? Color.predktMuted.opacity(0.3) : .white)
                    .lineLimit(1).minimumScaleFactor(0.8)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(answer.probability)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isLocked ? Color.predktLime : Color.predktMuted.opacity(0.55))
                    Text("+\(xp) XP")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(isLocked ? Color.predktLime : Color.predktMuted.opacity(0.4))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isLocked ? Color.predktLime.opacity(0.08) : Color.predktCard)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(isLocked ? Color.predktLime.opacity(0.4) : Color.predktBorder,
                                lineWidth: isLocked ? 1.5 : 1))
            )
            .opacity(isConflicted ? 0.28 : 1.0)
            .scaleEffect(isLocked ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isLocked)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicted)
    }
}

// MARK: - Score Chip  (3-column compact grid for correct score markets)

struct ScoreChipView: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false

    var isLocked:     Bool { viewModel.isLocked(answer) }
    var isConflicted: Bool { viewModel.conflicts(answer) }
    var xp: Int { isLive ? answer.liveXpValue() : answer.xpValue }

    var body: some View {
        Button {
            guard !isConflicted else { return }
            viewModel.lockAnswer(answer)
        } label: {
            VStack(spacing: 3) {
                Text(answer.shortLabel)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(isLocked ? .black : .white)
                Text("\(answer.probability)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isLocked ? .black.opacity(0.5) : Color.predktMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isLocked ? Color.predktLime : Color.predktCard)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isLocked ? .clear : Color.predktBorder, lineWidth: 1))
            .opacity(isConflicted ? 0.22 : 1.0)
            .scaleEffect(isLocked ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLocked)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicted)
    }
}

// MARK: - Player Select Chip  (2-column grid, max 2 per category)

struct PlayerSelectChip: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel
    var isLive: Bool = false
    var onMaxReached: () -> Void

    var isSelected: Bool  { viewModel.isLocked(answer) }
    var xp: Int           { viewModel.effectiveXP(for: answer, isLive: isLive) }

    var body: some View {
        Button {
            if viewModel.isAtPlayerLimit(answer) {
                onMaxReached()
            } else {
                viewModel.lockAnswer(answer)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(answer.label)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isSelected ? .black : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                HStack {
                    Text("\(answer.probability)% likely")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .black.opacity(0.45) : Color.predktMuted)
                    Spacer()
                    Text("+\(xp) XP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? .black.opacity(0.55) : Color.predktLime)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.predktLime : Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Questions Skeleton

struct QuestionsSkeleton: View {
    @State private var shimmer = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(shimmer ? 0.08 : 0.04))
                            .frame(width: 200, height: 22)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(shimmer ? 0.06 : 0.03))
                                    .frame(height: 120)
                            }
                        }
                    }
                    .padding(16).background(Color.predktCard).cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.predktBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16).padding(.top, 16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}

// MARK: - Locked Answers Banner (kept for compatibility)

struct LockedAnswersBanner: View {
    @ObservedObject var viewModel: PredictViewModel
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.isCombo ? "⚡ \(viewModel.lockedAnswers.count)-PICK COMBO" : "⚡ SINGLE PLAY")
                    .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktLime).kerning(1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.lockedAnswers) { answer in
                            Text(answer.shortLabel)
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.predktLime.opacity(0.15)).cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.predktLime.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 2) {
                Text("+\(viewModel.totalXP)")
                    .font(.system(size: 18, weight: .black)).foregroundStyle(Color.predktLime)
                Text("XP").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.7))
            }
        }
        .padding(12).background(Color.predktLime.opacity(0.07)).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktLime.opacity(0.2), lineWidth: 1))
        .padding(.bottom, 12)
    }
}

// MARK: - Date Chip

struct GameDateChip: View {
    let date: Date; let isSelected: Bool; let hasMatches: Bool; let action: () -> Void
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(isToday ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 8, weight: .black)).kerning(1)
                Text(date.formatted(.dateTime.day())).font(.system(size: 17, weight: .black))
                if hasMatches {
                    Circle().fill(isSelected ? Color.black.opacity(0.4) : Color.predktLime).frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(isSelected ? .black : hasMatches ? .white : Color.predktMuted)
            .frame(width: 52, height: 64)
            .background(isSelected ? Color.predktLime : Color.predktCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.clear : Color.predktBorder, lineWidth: 1))
        }
    }
}

// MARK: - Empty State

struct EmptyMatchesCard: View {
    let onNext: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("🏟️").font(.system(size: 48))
            Text("No matches today").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Text("Swipe left or tap below to check the next day")
                .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text("Next Day").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                }
                .padding(.horizontal, 24).padding(.vertical, 12).background(Color.predktLime).cornerRadius(12)
            }
        }
        .padding(40).frame(maxWidth: .infinity)
        .background(Color.predktCard).cornerRadius(20)
        .padding(.horizontal, 20).padding(.top, 60)
    }
}
