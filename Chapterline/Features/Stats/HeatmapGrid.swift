import SwiftUI

enum HeatmapPaint {
    static func color(for wall: TimeInterval) -> Color {
        if wall <= 0 { return Theme.fill }
        let minutes = wall / 60
        if minutes < 15 { return Color.accentColor.opacity(0.28) }
        if minutes < 45 { return Color.accentColor.opacity(0.5) }
        if minutes < 90 { return Color.accentColor.opacity(0.75) }
        return Color.accentColor
    }
}

enum HeatmapLayout {
    static let cellSize: CGFloat = 18
    static let spacing: CGFloat = 3
    static let cornerRadius: CGFloat = 3
    static let weekdayWidth: CGFloat = 14
    static let scrollWeekThreshold = 12
    static let todayLineWidth: CGFloat = 1.75
}

struct HeatmapGrid: View {
    let days: [HeatmapDay]
    let period: StatsPeriod
    let usesTrueBlack: Bool
    let sessionsForDay: (Date) -> [SessionRow]
    let onOpenBook: (UUID) -> Void

    @State private var selectedDay: HeatmapDay?

    private var calendar: Calendar { .current }
    private var now: Date { Date() }

    private var weekIndices: [Int] {
        let maxWeek = days.map(\.weekIndex).max() ?? 0
        return Array(0...maxWeek)
    }

    private var cellsByWeek: [Int: [Int: HeatmapDay]] {
        var lookup: [Int: [Int: HeatmapDay]] = [:]
        for day in days {
            lookup[day.weekIndex, default: [:]][day.weekday] = day
        }
        return lookup
    }

    private var shouldScroll: Bool {
        weekIndices.count > HeatmapLayout.scrollWeekThreshold
    }

    private var showMonthTicks: Bool {
        ListeningStatsMath.showsMonthTicks(for: period)
    }

    private var tickLetters: [Int: String] {
        Dictionary(
            uniqueKeysWithValues: ListeningStatsMath.monthTicks(days: days, calendar: calendar).map {
                ($0.weekIndex, $0.letter)
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            weekdayGutter
            if shouldScroll {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        weekStack
                    }
                    .onAppear { scrollToToday(proxy) }
                    .onChange(of: period) { _, _ in
                        scrollToToday(proxy)
                    }
                    .onChange(of: days.count) { _, _ in
                        scrollToToday(proxy)
                    }
                }
            } else {
                weekStack
            }
        }
        .frame(minHeight: 144)
        .accessibilityElement(children: .contain)
    }

    private var weekdayGutter: some View {
        VStack(spacing: HeatmapLayout.spacing) {
            ForEach(0..<7, id: \.self) { weekday in
                Text(weekdayLetter(weekday))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: HeatmapLayout.weekdayWidth, height: HeatmapLayout.cellSize, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private var weekStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: HeatmapLayout.spacing) {
                ForEach(weekIndices, id: \.self) { week in
                    weekColumn(week)
                        .id(week)
                }
            }
            if showMonthTicks {
                HStack(spacing: HeatmapLayout.spacing) {
                    ForEach(weekIndices, id: \.self) { week in
                        Text(tickLetters[week] ?? "")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: HeatmapLayout.cellSize, alignment: .center)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func weekColumn(_ week: Int) -> some View {
        VStack(spacing: HeatmapLayout.spacing) {
            ForEach(0..<7, id: \.self) { weekday in
                if let day = cellsByWeek[week]?[weekday] {
                    HeatmapDayCell(
                        day: day,
                        isToday: calendar.isDate(day.day, inSameDayAs: now),
                        isPresented: selectedDay?.id == day.id,
                        usesTrueBlack: usesTrueBlack,
                        loadSessions: { sessionsForDay(day.day) },
                        onPresent: { selectedDay = day },
                        onDismiss: { selectedDay = nil },
                        onOpenBook: { id in
                            selectedDay = nil
                            onOpenBook(id)
                        }
                    )
                } else {
                    Color.clear
                        .frame(width: HeatmapLayout.cellSize, height: HeatmapLayout.cellSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy) {
        guard let last = weekIndices.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(last, anchor: .trailing)
        }
    }

    private func weekdayLetter(_ weekday: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = (weekday + calendar.firstWeekday - 1 + 7) % 7
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}

private struct HeatmapDayCell: View {
    let day: HeatmapDay
    let isToday: Bool
    let isPresented: Bool
    let usesTrueBlack: Bool
    let loadSessions: () -> [SessionRow]
    let onPresent: () -> Void
    let onDismiss: () -> Void
    let onOpenBook: (UUID) -> Void

    var body: some View {
        Button(action: onPresent) {
            RoundedRectangle(cornerRadius: HeatmapLayout.cornerRadius, style: .continuous)
                .fill(HeatmapPaint.color(for: day.wallDuration))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: HeatmapLayout.cornerRadius, style: .continuous)
                            .strokeBorder(Theme.textPrimary, lineWidth: HeatmapLayout.todayLineWidth)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: HeatmapLayout.cellSize, height: HeatmapLayout.cellSize)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onPresent() }
        )
        .accessibilityLabel(
            ListeningStatsMath.heatmapSpokenLabel(day: day.day, wallDuration: day.wallDuration)
        )
        .accessibilityHint(day.wallDuration > 0 ? "Shows sessions for this day" : "No sessions this day")
        .accessibilityAddTraits(isPresented ? .isSelected : [])
        .popover(isPresented: Binding(
            get: { isPresented },
            set: { if !$0 { onDismiss() } }
        )) {
            DaySessionsSheet(
                day: day.day,
                wallDuration: day.wallDuration,
                sessions: loadSessions(),
                usesTrueBlack: usesTrueBlack,
                onOpenBook: onOpenBook
            )
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .frame(minWidth: 320, minHeight: 280)
        }
    }
}
