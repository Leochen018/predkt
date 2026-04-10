import SwiftUI

// MARK: - Predict View

struct PredictView: View {
    @StateObject private var viewModel = PredictViewModel()
    @State private var showingQuestions = false
    @State private var selectedMatch: Match?
    @State private var myPicksCount = 0

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PLAY")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Pick your winners")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                // Date carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<14) { i in
                            let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) ?? Date()
                            GameDateChip(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                                action: { viewModel.selectedDate = date }
                            )
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }
                .background(Color.predktCard.opacity(0.5))

                if viewModel.isLoading {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.predktLime))
                        Text("Loading matches…").font(.system(size: 13)).foregroundStyle(Color.predktMuted)
                    }
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    Text(error).foregroundStyle(Color.predktCoral).padding(20).multilineTextAlignment(.center)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if viewModel.filteredMatches.isEmpty {
                                EmptyMatchesCard()
                            } else {
                                HStack {
                                    Text("\(viewModel.filteredMatches.count) CHALLENGES AVAILABLE")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.predktMuted).kerning(1.5)
                                    Spacer()
                                }
                                .padding(.horizontal, 20).padding(.top, 8)

                                ForEach(viewModel.filteredMatches, id: \.id) { match in
                                    ChallengeCard(match: match) {
                                        viewModel.clearAnswers()
                                        selectedMatch = match
                                        showingQuestions = true
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            Spacer().frame(height: 30)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .onAppear { Task { await viewModel.loadMatches() } }
        .sheet(isPresented: $showingQuestions) {
            if let match = selectedMatch {
                QuestionsSheetView(
                    match: match,
                    viewModel: viewModel,
                    myPicksCount: myPicksCount,
                    isPresented: $showingQuestions
                )
            }
        }
    }
}

// MARK: - Challenge Card

struct ChallengeCard: View {
    let match: Match
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 6) {
                    if match.isLive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.predktCoral).frame(width: 6, height: 6)
                            Text("LIVE \(match.elapsed.map { "\($0)'" } ?? "")")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.predktCoral).kerning(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.predktCoral.opacity(0.12)).cornerRadius(20)
                    } else {
                        Text("🕐 \(match.kickoffTime)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.predktLime)
                    }
                    Text("·").foregroundStyle(Color.predktMuted)
                    Text(match.competition)
                        .font(.system(size: 10)).foregroundStyle(Color.predktMuted).lineLimit(1)
                    Spacer()
                    Text("PLAY →")
                        .font(.system(size: 9, weight: .black)).foregroundStyle(Color.predktLime).kerning(1)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

                // Teams
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 8) {
                        TeamBadgeView(url: match.homeLogo).frame(width: 40, height: 40)
                        Text(match.home)
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        if match.isLive || match.isFinished {
                            Text(match.score)
                                .font(.system(size: 26, weight: .black)).foregroundStyle(.white)
                        } else {
                            Text("VS")
                                .font(.system(size: 16, weight: .black)).foregroundStyle(Color.predktMuted)
                        }
                    }
                    .frame(width: 56)

                    VStack(spacing: 8) {
                        TeamBadgeView(url: match.awayLogo).frame(width: 40, height: 40)
                        Text(match.away)
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .background(Color.predktCard)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(match.isLive ? Color.predktCoral.opacity(0.4) : Color.predktBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Questions Sheet

struct QuestionsSheetView: View {
    let match: Match
    @ObservedObject var viewModel: PredictViewModel
    let myPicksCount: Int
    @Binding var isPresented: Bool

    var questions: [PredictViewModel.Question] { viewModel.getQuestions(for: match) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Match header
                VStack(spacing: 12) {
                    HStack {
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.predktMuted)
                                .padding(8).background(Color.white.opacity(0.07)).cornerRadius(8)
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
                        TeamBadgeView(url: match.homeLogo).frame(width: 36, height: 36)
                        VStack(spacing: 2) {
                            Text(match.displayName)
                                .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(match.competition)
                                .font(.system(size: 11)).foregroundStyle(Color.predktMuted)
                        }
                        TeamBadgeView(url: match.awayLogo).frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, 20)

                    if !viewModel.lockedAnswers.isEmpty {
                        LockedAnswersBanner(viewModel: viewModel).padding(.horizontal, 20)
                    }
                }
                .background(Color.predktCard)
                .padding(.bottom, 1)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(questions) { question in
                            QuestionCard(question: question, viewModel: viewModel)
                        }
                        Spacer().frame(height: viewModel.lockedAnswers.isEmpty ? 40 : 110)
                    }
                    .padding(.horizontal, 16).padding(.top, 16)
                }
            }

            // Floating Lock In button
            if !viewModel.lockedAnswers.isEmpty {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.predktBg.opacity(0), Color.predktBg],
                        startPoint: .top, endPoint: .bottom
                    ).frame(height: 24)

                    Button(action: {
                        Task {
                            let success = await viewModel.submitPlays(match: match, myPicksCount: myPicksCount)
                            if success { isPresented = false }
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
                                    Text("XP").font(.system(size: 14, weight: .black)).foregroundStyle(.black.opacity(0.6))
                                }
                            }
                        }
                        .padding(.horizontal, 24).frame(height: 62)
                        .background(Color.predktLime)
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Question Card

struct QuestionCard: View {
    let question: PredictViewModel.Question
    @ObservedObject var viewModel: PredictViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() } }) {
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
        .background(Color.predktCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.predktBorder, lineWidth: 1))
    }
}

// MARK: - Answer Poll Row

struct AnswerPollRow: View {
    let answer: PredictViewModel.Answer
    @ObservedObject var viewModel: PredictViewModel

    var isLocked: Bool     { viewModel.isLocked(answer) }
    var isConflicted: Bool { viewModel.conflicts(answer) }

    var xpColour: Color {
        switch answer.probability {
        case 0..<30: return Color.predktCoral
        case 30..<55: return Color.predktAmber
        default:     return Color.predktLime
        }
    }

    var body: some View {
        Button(action: { if !isConflicted { viewModel.lockAnswer(answer) } }) {
            ZStack(alignment: .leading) {
                // Poll fill bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isLocked ? Color.predktLime.opacity(0.18) : Color.white.opacity(0.04))
                        .frame(
                            width: isLocked
                                ? geo.size.width
                                : geo.size.width * CGFloat(answer.communityPercent) / 100
                        )
                        .animation(.easeOut(duration: 0.3), value: isLocked)
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(isLocked ? Color.predktLime : Color.white.opacity(0.15), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isLocked {
                            Circle().fill(Color.predktLime).frame(width: 14, height: 14)
                        }
                    }

                    Text(answer.label)
                        .font(.system(size: 14, weight: isLocked ? .bold : .medium))
                        .foregroundStyle(
                            isLocked ? .white :
                            isConflicted ? Color.predktMuted.opacity(0.4) :
                            Color.predktMuted
                        )
                        .lineLimit(2)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(answer.xpValue) XP")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(isLocked ? Color.predktLime : xpColour)
                        Text(answer.probabilityDisplay)
                            .font(.system(size: 10))
                            .foregroundStyle(isConflicted ? Color.predktMuted.opacity(0.3) : Color.predktMuted)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isLocked ? Color.predktLime.opacity(0.5) : Color.predktBorder,
                                lineWidth: 1
                            )
                    )
            )
            .opacity(isConflicted ? 0.35 : 1.0)
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
                            Text(answer.shortLabel)
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.predktLime.opacity(0.15)).cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.predktLime.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 2) {
                Text("+\(viewModel.totalXP)").font(.system(size: 18, weight: .black)).foregroundStyle(Color.predktLime)
                Text("XP").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.predktLime.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color.predktLime.opacity(0.07))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.predktLime.opacity(0.2), lineWidth: 1))
        .padding(.bottom, 12)
    }
}

// MARK: - Date Chip

struct GameDateChip: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(isToday ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 8, weight: .black)).kerning(1)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .black))
            }
            .foregroundStyle(isSelected ? .black : Color.predktMuted)
            .frame(width: 52, height: 60)
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
    var body: some View {
        VStack(spacing: 16) {
            Text("🏟️").font(.system(size: 48))
            Text("No challenges today")
                .font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Text("Check another date or follow more leagues in your interests.")
                .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
        }
        .padding(40).frame(maxWidth: .infinity)
        .background(Color.predktCard).cornerRadius(20)
        .padding(.horizontal, 20).padding(.top, 60)
    }
}
