import SwiftUI
import Supabase

// MARK: - PredictView

struct PredictView: View {
    @StateObject private var viewModel = PredictViewModel()
    @State private var showingQuestions = false
    @State private var selectedMatch: Match?
    @State private var myPicksCount = 0

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
                    // Count distinct matches, not individual picks
                    myPicksCount = Set(picks.map { $0.match }).count
                }
            }
        }
        .sheet(isPresented: $showingQuestions) {
            if let match = selectedMatch {
                QuestionsSheetView(
                    match: match,
                    viewModel: viewModel,
                    myPicksCount: myPicksCount,
                    isPresented: $showingQuestions,
                    onSubmit: {
                        Task {
                            if let picks = try? await SupabaseManager.shared.fetchMyPicks() {
                                myPicksCount = picks.count
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedDate = date
                }
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
                    viewModel.clearAnswers()
                    selectedMatch = match
                    showingQuestions = true
                },
                onNextDay:   { viewModel.goToNextDay() },
                onSwipeLeft: { viewModel.goToNextDay() },
                onSwipeRight:{ viewModel.goToPreviousDay() }
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = .current
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<60, id: \.self) { i in
                        let date = Calendar.current.date(
                            byAdding: .day, value: i,
                            to: Calendar.current.startOfDay(for: Date())
                        ) ?? Date()
                        let isSelected  = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        let dateKey     = Self.localFmt.string(from: date)
                        let hasMatches  = matchesLoaded && datesWithMatches.contains(dateKey)

                        GameDateChip(
                            date: date, isSelected: isSelected, hasMatches: hasMatches,
                            action: { onSelect(date) }
                        )
                        .id(i)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .onChange(of: selectedDate) {
                let today = Calendar.current.startOfDay(for: Date())
                let days  = Calendar.current.dateComponents([.day], from: today, to: selectedDate).day ?? 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(max(0, min(days, 59)), anchor: .center)
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
            if groups.isEmpty {
                EmptyMatchesCard(onNext: onNextDay)
            } else {
                matchList
            }
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
                    LeagueSection(
                        league: group.league,
                        matches: group.matches,
                        isFavourite: group.isFavourite,
                        isFavouriteMatch: isFavouriteMatch,
                        onSelect: onSelect
                    )
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
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(isFavourite ? Color.predktAmber : Color.predktLime)
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
                        MatchRowButton(
                            match: match,
                            isFavourite: isFavouriteMatch(match),
                            onTap: { onSelect(match) }
                        )
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

// MARK: - MatchRowButton (Equatable — skips re-render if nothing changed)

private struct MatchRowButton: View, Equatable {
    let match: Match
    let isFavourite: Bool
    let onTap: () -> Void

    static func == (lhs: MatchRowButton, rhs: MatchRowButton) -> Bool {
        lhs.match.id        == rhs.match.id &&
        lhs.match.status    == rhs.match.status &&
        lhs.match.homeGoals == rhs.match.homeGoals &&
        lhs.match.awayGoals == rhs.match.awayGoals &&
        lhs.isFavourite     == rhs.isFavourite
    }

    var body: some View {
        Button(action: onTap) {
            MatchRowContent(match: match, isFavourite: isFavourite)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct MatchRowContent: View {
    let match: Match
    let isFavourite: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Time column
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
                    Text(match.home)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
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
                    Text(match.away)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).multilineTextAlignment(.trailing)
                    TeamBadgeView(url: match.awayLogo, teamName: match.away).frame(width: 28, height: 28)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            if isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.predktAmber).frame(width: 28)
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
            }
            .padding(.top, 12)
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

// MARK: - Questions Sheet

struct QuestionsSheetView: View {
    let match: Match
    @ObservedObject var viewModel: PredictViewModel
    let myPicksCount: Int
    @Binding var isPresented: Bool
    let onSubmit: () -> Void
    @State private var questions: [PredictViewModel.Question] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.predktBg.ignoresSafeArea()
            VStack(spacing: 0) {
                matchHeader
                if viewModel.isLoadingOdds {
                    QuestionsSkeleton()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 20) {
                            ForEach(questions) { question in
                                QuestionCard(question: question, viewModel: viewModel)
                            }
                            Color.clear.frame(height: viewModel.lockedAnswers.isEmpty ? 40 : 110)
                        }
                        .padding(.horizontal, 16).padding(.top, 16)
                    }
                }
            }
            if !viewModel.lockedAnswers.isEmpty { submitBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadOdds(for: match)
            questions = viewModel.getQuestions(for: match)
        }
    }

    private var matchHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.predktMuted).padding(8)
                        .background(Color.white.opacity(0.07)).cornerRadius(8)
                }
                Spacer()
                if match.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                        Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                            .font(.system(size: 10, weight: .black)).foregroundStyle(Color.predktCoral)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)

            HStack(spacing: 16) {
                TeamBadgeView(url: match.homeLogo, teamName: match.home).frame(width: 36, height: 36)
                VStack(spacing: 2) {
                    Text(match.displayName)
                        .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Text(match.competition).font(.system(size: 11)).foregroundStyle(Color.predktMuted)
                        if !match.isLive, !match.isFinished {
                            Text("·").foregroundStyle(Color.predktMuted)
                            Text("\(match.matchDate) · \(match.kickoffTime)")
                                .font(.system(size: 11)).foregroundStyle(Color.predktLime)
                        }
                    }
                }
                TeamBadgeView(url: match.awayLogo, teamName: match.away).frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)

            if !viewModel.lockedAnswers.isEmpty {
                LockedAnswersBanner(viewModel: viewModel).padding(.horizontal, 20)
            }
        }
        .background(Color.predktCard).padding(.bottom, 1)
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.predktBg.opacity(0), Color.predktBg],
                startPoint: .top, endPoint: .bottom
            ).frame(height: 24)

            Button(action: {
                Task {
                    let ok = await viewModel.submitPlays(match: match, myPicksCount: myPicksCount)
                    if ok { isPresented = false; onSubmit() }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isCombo ? "\(viewModel.lockedAnswers.count)-PICK COMBO" : "LOCK IN PLAY")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black.opacity(0.6)).kerning(1)
                        Text(viewModel.lockedAnswers.map { $0.shortLabel }.joined(separator: " + "))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.black).lineLimit(1)
                    }
                    Spacer()
                    if viewModel.isSubmitting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        HStack(spacing: 4) {
                            Text("+\(viewModel.totalXP)")
                                .font(.system(size: 22, weight: .black)).foregroundStyle(.black)
                            Text("XP")
                                .font(.system(size: 14, weight: .black)).foregroundStyle(.black.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 24).frame(height: 62).background(Color.predktLime)
            }
            .disabled(viewModel.isSubmitting)
        }
    }
}

// MARK: - Questions Skeleton

struct QuestionsSkeleton: View {
    @State private var shimmer = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(shimmer ? 0.08 : 0.04)).frame(width: 140, height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(shimmer ? 0.08 : 0.04)).frame(height: 14)
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(shimmer ? 0.06 : 0.03)).frame(height: 52)
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

// MARK: - Question Card

struct QuestionCard: View {
    let question: PredictViewModel.Question
    @ObservedObject var viewModel: PredictViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 8) {
                    Text(question.category)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.predktLime).kerning(1.5)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktMuted)
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Text(question.prompt)
                    .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.bottom, 14)

                VStack(spacing: 8) {
                    ForEach(question.answers) { answer in
                        AnswerPollRow(answer: answer, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .background(Color.predktCard).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.predktBorder, lineWidth: 1))
    }
}

// MARK: - ✅ Answer Poll Row
// Shows: ○  Player Name          28%  +18 XP
//                               TAP TO REMOVE (when locked)

struct AnswerPollRow: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel

    var isLocked:     Bool { viewModel.isLocked(answer) }
    var isConflicted: Bool { viewModel.conflicts(answer) }

    var xpColour: Color {
        answer.probability < 30  ? Color.predktCoral
            : answer.probability < 55 ? Color.predktAmber
            : Color.predktLime
    }

    var body: some View {
        Button(action: {
            guard !isConflicted else { return }
            viewModel.lockAnswer(answer)
        }) {
            ZStack(alignment: .leading) {
                // Poll bar behind the row
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isLocked ? Color.predktLime.opacity(0.18) : Color.white.opacity(0.04))
                        .frame(width: isLocked
                               ? geo.size.width
                               : geo.size.width * CGFloat(answer.communityPercent) / 100)
                        .animation(.easeOut(duration: 0.3), value: isLocked)
                }

                HStack(spacing: 12) {
                    // Radio circle
                    ZStack {
                        Circle()
                            .stroke(
                                isLocked ? Color.predktLime : Color.white.opacity(0.15),
                                lineWidth: 2
                            )
                            .frame(width: 22, height: 22)
                        if isLocked {
                            Circle().fill(Color.predktLime).frame(width: 14, height: 14)
                        }
                    }

                    // ✅ Player / answer name — full name displayed
                    Text(answer.label)
                        .font(.system(size: 14, weight: isLocked ? .bold : .medium))
                        .foregroundStyle(
                            isConflicted ? Color.predktMuted.opacity(0.4)
                                : isLocked  ? .white
                                : .white
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    // ✅ Right side: "28%  +18 XP" on one line, "TAP TO REMOVE" below when locked
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            // Probability percentage
                            Text(answer.probabilityDisplay)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    isConflicted ? Color.predktMuted.opacity(0.3) : Color.predktMuted
                                )

                            // XP value
                            Text("+\(answer.xpValue) XP")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(isLocked ? Color.predktLime : xpColour)
                        }

                        if isLocked {
                            Text("TAP TO REMOVE")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.predktLime.opacity(0.6))
                                .kerning(0.5)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isLocked ? Color.predktLime.opacity(0.5) : Color.predktBorder,
                                lineWidth: isLocked ? 1.5 : 1
                            )
                    )
            )
            .opacity(isConflicted ? 0.35 : 1.0)
            .scaleEffect(isLocked ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isLocked)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicted)
    }
}

// MARK: - Locked Answers Banner

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
                            // ✅ Now shows player last name e.g. "Haaland" not "👤"
                            Text(answer.shortLabel)
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.predktLime.opacity(0.15)).cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.predktLime.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 2) {
                Text("+\(viewModel.totalXP)")
                    .font(.system(size: 18, weight: .black)).foregroundStyle(Color.predktLime)
                Text("XP")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.7))
            }
        }
        .padding(12).background(Color.predktLime.opacity(0.07)).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktLime.opacity(0.2), lineWidth: 1))
        .padding(.bottom, 12)
    }
}

// MARK: - Date Chip

struct GameDateChip: View {
    let date: Date
    let isSelected: Bool
    let hasMatches: Bool
    let action: () -> Void

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(isToday ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 8, weight: .black)).kerning(1)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .black))
                if hasMatches {
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.4) : Color.predktLime)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(isSelected ? .black : hasMatches ? .white : Color.predktMuted)
            .frame(width: 52, height: 64)
            .background(isSelected ? Color.predktLime : Color.predktCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : Color.predktBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Empty State

struct EmptyMatchesCard: View {
    let onNext: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("🏟️").font(.system(size: 48))
            Text("No matches today")
                .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Text("Swipe left or tap below to check the next day")
                .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text("Next Day").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color.predktLime).cornerRadius(12)
            }
        }
        .padding(40).frame(maxWidth: .infinity)
        .background(Color.predktCard).cornerRadius(20)
        .padding(.horizontal, 20).padding(.top, 60)
    }
}
