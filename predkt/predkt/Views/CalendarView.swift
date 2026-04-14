import SwiftUI

// MARK: - Calendar View

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var selectedDate: Date = Date()
    @State private var showingDayDetail = false

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HISTORY")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(2)
                        Text("Your predictions")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                .background(Color.predktBg)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Monthly calendar
                        MonthCalendarView(
                            viewModel: viewModel,
                            selectedDate: $selectedDate,
                            onSelectDate: { date in
                                selectedDate = date
                                Task { await viewModel.loadPicks(for: date) }
                                showingDayDetail = true
                            }
                        )
                        .padding(.horizontal, 16)

                        // Summary stats
                        StreakSummaryCard(viewModel: viewModel)
                            .padding(.horizontal, 16)

                        // Today's picks preview
                        // Full pick history grouped by date
                        if !viewModel.picksByDate.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PREDICTION HISTORY")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.predktMuted).kerning(1.5)
                                    .padding(.horizontal, 16)

                                ForEach(viewModel.picksByDate, id: \.date) { group in
                                    PickHistoryDateBox(date: group.date, picks: group.picks)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        Spacer().frame(height: 80)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadAllPicks()
                await viewModel.loadPicks(for: Date())
            }
        }
        .sheet(isPresented: $showingDayDetail) {
            DayDetailSheet(date: selectedDate, viewModel: viewModel)
        }
    }
}

// MARK: - Month Calendar

struct MonthCalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var selectedDate: Date
    let onSelectDate: (Date) -> Void

    @State private var displayMonth: Date = Date()

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["M","T","W","T","F","S","S"]

    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                        .padding(8).background(Color.predktCard).cornerRadius(8)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                Spacer()
                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                        .padding(8).background(Color.predktCard).cornerRadius(8)
                }
            }

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.predktMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: columns, spacing: 6) {
                // Leading empty cells
                ForEach(0..<leadingSpaces, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }

                // Days
                ForEach(daysInMonth, id: \.self) { date in
                    let picks = viewModel.picks(for: date)
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    let isToday    = Calendar.current.isDateInToday(date)
                    let isFuture   = date > Date()

                    Button(action: { if !isFuture { onSelectDate(date) } }) {
                        VStack(spacing: 3) {
                            Text(dayNumber(date))
                                .font(.system(size: 13, weight: isToday ? .black : .semibold))
                                .foregroundStyle(
                                    isSelected ? .black :
                                    isToday    ? Color.predktLime :
                                    isFuture   ? Color.predktMuted.opacity(0.3) : .white
                                )

                            // Pick indicator dots
                            if !picks.isEmpty && !isFuture {
                                HStack(spacing: 2) {
                                    ForEach(Array(picks.prefix(3).enumerated()), id: \.offset) { _, pick in
                                        Circle()
                                            .fill(dotColour(pick))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            } else {
                                Color.clear.frame(height: 4)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(
                            isSelected ? Color.predktLime :
                            isToday    ? Color.predktLime.opacity(0.12) :
                            !picks.isEmpty ? pickBackground(picks) : Color.clear
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isToday && !isSelected ? Color.predktLime.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isFuture)
                }
            }
        }
        .padding(16)
        .background(Color.predktCard)
        .cornerRadius(20)
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }

    private var leadingSpaces: Int {
        let cal  = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.weekday], from: startOfMonth)
        return (comps.weekday! - 2 + 7) % 7
    }

    private var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year,.month], from: displayMonth))!
    }

    private var daysInMonth: [Date] {
        let cal   = Calendar.current
        let range = cal.range(of: .day, in: .month, for: displayMonth)!
        return range.compactMap { day -> Date? in
            cal.date(bySetting: .day, value: day, of: startOfMonth)
        }
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }

    private func changeMonth(_ delta: Int) {
        displayMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayMonth) ?? displayMonth
    }

    private func dotColour(_ pick: Pick) -> Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }

    private func pickBackground(_ picks: [Pick]) -> Color {
        let correct = picks.filter { $0.result == "correct" }.count
        let wrong   = picks.filter { $0.result == "wrong" }.count
        if correct > wrong  { return Color.predktLime.opacity(0.08) }
        if wrong   > correct { return Color.predktCoral.opacity(0.08) }
        return Color.predktAmber.opacity(0.08)
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) var dismiss

    private var displayDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; f.timeZone = .current
        return f.string(from: date)
    }

    private var picks: [Pick] { viewModel.picks(for: date) }

    // Stats for this day
    private var correct: Int { picks.filter { $0.result == "correct" }.count }
    private var wrong:   Int { picks.filter { $0.result == "wrong"   }.count }
    private var pending: Int { picks.filter { $0.result == "pending" }.count }
    private var xpEarned: Int { picks.compactMap { $0.points_earned }.reduce(0, +) }

    var body: some View {
        ZStack {
            Color.predktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayDate.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.predktMuted).kerning(1.5)
                        Text("\(picks.count) play\(picks.count == 1 ? "" : "s")")
                            .font(.system(size: 22, weight: .black)).foregroundStyle(.white)
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

                if picks.isEmpty {
                    VStack(spacing: 12) {
                        Text("📭").font(.system(size: 44))
                        Text("No plays on this day")
                            .font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                        Text("Head to the Play tab to make your predictions")
                            .font(.system(size: 13)).foregroundStyle(Color.predktMuted).multilineTextAlignment(.center)
                    }
                    .padding(.top, 80).padding(.horizontal, 40)
                    Spacer()
                } else {
                    // Day summary bar
                    HStack(spacing: 0) {
                        DayStat(value: "\(correct)", label: "CORRECT", colour: Color.predktLime)
                        Divider().background(Color.predktBorder).frame(height: 40)
                        DayStat(value: "\(wrong)",   label: "WRONG",   colour: Color.predktCoral)
                        Divider().background(Color.predktBorder).frame(height: 40)
                        DayStat(value: "\(pending)", label: "PENDING", colour: Color.predktAmber)
                        Divider().background(Color.predktBorder).frame(height: 40)
                        DayStat(value: xpEarned >= 0 ? "+\(xpEarned)" : "\(xpEarned)", label: "XP", colour: xpEarned >= 0 ? Color.predktLime : Color.predktCoral)
                    }
                    .padding(.vertical, 12)
                    .background(Color.predktCard.opacity(0.5))

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(picks) { pick in
                                CalendarPickCard(pick: pick)
                            }
                            Spacer().frame(height: 40)
                        }
                        .padding(16)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct DayStat: View {
    let value: String; let label: String; let colour: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black)).foregroundStyle(colour)
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calendar Pick Card (detailed)

struct CalendarPickCard: View {
    let pick: Pick

    private var resultColour: Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }
    private var resultIcon: String {
        switch pick.result {
        case "correct": return "checkmark.circle.fill"
        case "wrong":   return "xmark.circle.fill"
        default:        return "clock.fill"
        }
    }
    private var resultLabel: String {
        switch pick.result {
        case "correct": return "CORRECT"
        case "wrong":   return "WRONG"
        default:        return "PENDING"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Result icon
            Image(systemName: resultIcon)
                .font(.system(size: 28))
                .foregroundStyle(resultColour)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(pick.match)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.predktMuted).lineLimit(1)
                Text(pick.market)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(resultLabel)
                    .font(.system(size: 9, weight: .black)).foregroundStyle(resultColour).kerning(1)
                if let earned = pick.points_earned {
                    Text(earned >= 0 ? "+\(earned) XP" : "\(earned) XP")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(earned >= 0 ? Color.predktLime : Color.predktCoral)
                } else {
                    Text("+\(pick.points_possible) XP")
                        .font(.system(size: 13, weight: .black)).foregroundStyle(Color.predktAmber)
                }
            }
        }
        .padding(14)
        .background(Color.predktCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(resultColour.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Compact Pick Row (for today section)

struct CalendarPickRow: View {
    let pick: Pick
    private var resultColour: Color {
        switch pick.result {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(resultColour).frame(width: 8, height: 8)
            Text(pick.market).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Text(pick.match).font(.system(size: 11)).foregroundStyle(Color.predktMuted).lineLimit(1)
        }
        .padding(12).background(Color.predktCard).cornerRadius(10)
    }
}

// MARK: - Streak Summary Card

struct StreakSummaryCard: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        HStack(spacing: 0) {
            StreakStat(icon: "🔥", value: "\(viewModel.currentWinStreak)", label: "WIN STREAK")
            Divider().background(Color.predktBorder).frame(height: 50)
            StreakStat(icon: "📅", value: "\(viewModel.dailyStreak)", label: "DAILY STREAK")
            Divider().background(Color.predktBorder).frame(height: 50)
            StreakStat(icon: "⚡", value: "\(viewModel.totalXP)", label: "TOTAL XP")
        }
        .padding(.vertical, 16)
        .background(Color.predktCard)
        .cornerRadius(16)
    }
}

struct StreakStat: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 20))
            Text(value).font(.system(size: 20, weight: .black)).foregroundStyle(Color.predktLime)
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(Color.predktMuted).kerning(1)
        }
        .frame(maxWidth: .infinity)
    }
}
// MARK: - Pick History Date Box

struct PickHistoryDateBox: View {
    let date: Date
    let picks: [Pick]

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    private var correct: Int { picks.filter { $0.result == "correct" }.count }
    private var wrong:   Int { picks.filter { $0.result == "wrong"   }.count }
    private var pending: Int { picks.filter { $0.result == "pending" }.count }
    private var xpTotal: Int { picks.compactMap { $0.points_earned }.reduce(0, +) }

    private var boxAccentColour: Color {
        if pending > 0     { return Color.predktAmber }
        if correct > wrong { return Color.predktLime }
        if wrong > 0       { return Color.predktCoral }
        return Color.predktMuted
    }

    // Group combo picks together — combos count as 1 prediction
    private var predictions: [[Pick]] {
        var groups: [[Pick]] = []
        var seen = Set<String>()
        for pick in picks {
            if let comboId = pick.combo_id, !comboId.isEmpty {
                if !seen.contains(comboId) {
                    seen.insert(comboId)
                    groups.append(picks.filter { $0.combo_id == comboId })
                }
            } else {
                groups.append([pick])
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date header
            HStack {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(boxAccentColour)
                        .frame(width: 3, height: 14).cornerRadius(2)
                    Text(dateLabel.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white).kerning(1)
                    Text("· \(predictions.count) prediction\(predictions.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.predktMuted)
                }
                Spacer()
                HStack(spacing: 8) {
                    if correct > 0 {
                        Label("\(correct)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktLime)
                    }
                    if wrong > 0 {
                        Label("\(wrong)", systemImage: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktCoral)
                    }
                    if pending > 0 {
                        Label("\(pending)", systemImage: "clock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.predktAmber)
                    }
                    if xpTotal != 0 {
                        Text(xpTotal > 0 ? "+\(xpTotal) XP" : "\(xpTotal) XP")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(xpTotal > 0 ? Color.predktLime : Color.predktCoral)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.predktCard)

            Divider().background(Color.predktBorder)

            VStack(spacing: 0) {
                ForEach(Array(predictions.enumerated()), id: \.offset) { index, group in
                    if group.count > 1 {
                        ComboPredictionCard(picks: group)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    } else if let pick = group.first {
                        CalendarPickCard(pick: pick)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    if index < predictions.count - 1 {
                        Divider().background(Color.predktBorder).padding(.horizontal, 12)
                    }
                }
            }
            .background(Color.predktBg)
        }
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(boxAccentColour.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Combo Prediction Card

struct ComboPredictionCard: View {
    let picks: [Pick]

    private var overallResult: String {
        if picks.allSatisfy({ $0.result == "correct" }) { return "correct" }
        if picks.contains(where: { $0.result == "wrong" }) { return "wrong" }
        return "pending"
    }
    private var resultColour: Color {
        switch overallResult {
        case "correct": return Color.predktLime
        case "wrong":   return Color.predktCoral
        default:        return Color.predktAmber
        }
    }
    private var resultIcon: String {
        switch overallResult {
        case "correct": return "checkmark.circle.fill"
        case "wrong":   return "xmark.circle.fill"
        default:        return "clock.fill"
        }
    }
    private var totalXP: Int {
        picks.compactMap { $0.points_earned }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: resultIcon)
                    .font(.system(size: 16)).foregroundStyle(resultColour)
                Text("\(picks.count)-PICK COMBO")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(resultColour).kerning(1)
                Spacer()
                if totalXP != 0 {
                    Text(totalXP > 0 ? "+\(totalXP) XP" : "\(totalXP) XP")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(totalXP > 0 ? Color.predktLime : Color.predktCoral)
                }
            }
            ForEach(picks) { pick in
                HStack(spacing: 8) {
                    Circle()
                        .fill(pick.result == "correct" ? Color.predktLime :
                              pick.result == "wrong"   ? Color.predktCoral : Color.predktAmber)
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pick.market)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(pick.match)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.predktMuted).lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.predktCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(resultColour.opacity(0.2), lineWidth: 1))
    }
}
