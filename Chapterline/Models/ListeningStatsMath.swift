import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .today: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .year: return "Last year"
        case .all: return "All time"
        }
    }
}

struct ListeningStatsInput: Equatable, Sendable {
    var bookID: UUID
    var startedAt: Date
    var endedAt: Date
    var wallDuration: TimeInterval
    var contentDuration: TimeInterval
    var endReason: SessionEndReason
    var counted: Bool
}

struct HeatmapDay: Identifiable, Equatable, Sendable {
    var day: Date
    var wallDuration: TimeInterval
    var weekIndex: Int
    var weekday: Int

    var id: Date { day }
}

struct BookListeningTotal: Identifiable, Equatable, Sendable {
    var bookID: UUID
    var title: String
    var author: String
    var wallDuration: TimeInterval
    var contentDuration: TimeInterval
    var sessionCount: Int

    var id: UUID { bookID }
}

struct ListeningReduction: Equatable, Sendable {
    var wallDuration: TimeInterval
    var contentDuration: TimeInterval
    var timeSaved: TimeInterval
    var sessionCount: Int
    var averageLength: TimeInterval
    var uniqueDays: Int
    var booksFinished: Int
    var booksStarted: Int
    var currentStreak: Int
    var longestStreak: Int
    var perBook: [BookListeningTotal]
    var heatmap: [HeatmapDay]

    static let empty = ListeningReduction(
        wallDuration: 0,
        contentDuration: 0,
        timeSaved: 0,
        sessionCount: 0,
        averageLength: 0,
        uniqueDays: 0,
        booksFinished: 0,
        booksStarted: 0,
        currentStreak: 0,
        longestStreak: 0,
        perBook: [],
        heatmap: []
    )
}

enum ListeningStatsMath: Sendable {
    nonisolated static let minimumSessionDuration: TimeInterval = 15

    nonisolated static func shouldCount(wallDuration: TimeInterval) -> Bool {
        wallDuration >= minimumSessionDuration
    }

    nonisolated static func contentDuration(wall: TimeInterval, rate: Double) -> TimeInterval {
        let safeRate = rate > 0 ? rate : 1
        return max(0, wall) * safeRate
    }

    nonisolated static func timeSaved(wall: TimeInterval, content: TimeInterval) -> TimeInterval {
        max(0, content - wall)
    }

    nonisolated static func periodStart(for period: StatsPeriod, now: Date, calendar: Calendar) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch period {
        case .today:
            return startOfToday
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: startOfToday)
        case .all:
            return nil
        }
    }

    nonisolated static func isInPeriod(date: Date, period: StatsPeriod, now: Date, calendar: Calendar) -> Bool {
        guard let start = periodStart(for: period, now: now, calendar: calendar) else { return true }
        return date >= start
    }

    nonisolated static func activityDays(
        sessions: [ListeningStatsInput],
        calendar: Calendar
    ) -> Set<Date> {
        var days: Set<Date> = []
        for session in sessions where session.counted {
            days.insert(calendar.startOfDay(for: session.startedAt))
        }
        return days
    }

    /// Current streak counts consecutive local calendar days ending today, or yesterday
    /// if today has no activity yet. Missing yesterday (and today) resets current to 0.
    nonisolated static func streaks(
        days: Set<Date>,
        now: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        let longest = longestStreak(in: days, calendar: calendar)
        guard !days.isEmpty else { return (0, 0) }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return (0, longest)
        }

        var current = 0
        var day = cursor
        while days.contains(day) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return (current, longest)
    }

    nonisolated static func longestStreak(in days: Set<Date>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let gap = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            if gap == 1 {
                run += 1
                longest = max(longest, run)
            } else if gap > 1 {
                run = 1
            }
        }
        return longest
    }

    nonisolated static func heatmap(
        sessions: [ListeningStatsInput],
        period: StatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> [HeatmapDay] {
        let counted = sessions.filter(\.counted)
        if counted.isEmpty, period == .all {
            return []
        }
        let end = calendar.startOfDay(for: now)
        let start: Date = {
            if let periodStart = periodStart(for: period, now: now, calendar: calendar) {
                return calendar.startOfDay(for: periodStart)
            }
            let first = counted.map(\.startedAt).min().map { calendar.startOfDay(for: $0) }
            let fallback = calendar.date(byAdding: .day, value: -119, to: end) ?? end
            return first ?? fallback
        }()
        let aligned = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start

        var wallByDay: [Date: TimeInterval] = [:]
        for session in counted {
            let day = calendar.startOfDay(for: session.startedAt)
            guard day >= start && day <= end else { continue }
            wallByDay[day, default: 0] += session.wallDuration
        }

        var days: [HeatmapDay] = []
        var cursor = start
        while cursor <= end {
            let offset = calendar.dateComponents([.day], from: aligned, to: cursor).day ?? 0
            let weekdayComponent = calendar.component(.weekday, from: cursor)
            let weekday = (weekdayComponent - calendar.firstWeekday + 7) % 7
            days.append(
                HeatmapDay(
                    day: cursor,
                    wallDuration: wallByDay[cursor] ?? 0,
                    weekIndex: max(0, offset / 7),
                    weekday: weekday
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    nonisolated static func reduce(
        sessions: [ListeningStatsInput],
        titles: [UUID: (title: String, author: String)],
        finished: [(bookID: UUID, at: Date)],
        period: StatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> ListeningReduction {
        let counted = sessions.filter(\.counted)
        let inPeriod = counted.filter { isInPeriod(date: $0.startedAt, period: period, now: now, calendar: calendar) }

        let wall = inPeriod.reduce(0) { $0 + $1.wallDuration }
        let content = inPeriod.reduce(0) { $0 + $1.contentDuration }
        let sessionCount = inPeriod.count
        let days = Set(inPeriod.map { calendar.startOfDay(for: $0.startedAt) })
        let booksStarted = Set(inPeriod.map(\.bookID)).count

        var finishedIDs = Set(inPeriod.filter { $0.endReason == .finished }.map(\.bookID))
        for item in finished where isInPeriod(date: item.at, period: period, now: now, calendar: calendar) {
            finishedIDs.insert(item.bookID)
        }

        var grouped: [UUID: BookListeningTotal] = [:]
        for session in inPeriod {
            let snapshot = titles[session.bookID]
            var total = grouped[session.bookID] ?? BookListeningTotal(
                bookID: session.bookID,
                title: snapshot?.title ?? "Unknown book",
                author: snapshot?.author ?? "",
                wallDuration: 0,
                contentDuration: 0,
                sessionCount: 0
            )
            if let snapshot {
                total.title = snapshot.title
                total.author = snapshot.author
            }
            total.wallDuration += session.wallDuration
            total.contentDuration += session.contentDuration
            total.sessionCount += 1
            grouped[session.bookID] = total
        }

        let allDays = activityDays(sessions: counted, calendar: calendar)
        let streak = streaks(days: allDays, now: now, calendar: calendar)

        return ListeningReduction(
            wallDuration: wall,
            contentDuration: content,
            timeSaved: timeSaved(wall: wall, content: content),
            sessionCount: sessionCount,
            averageLength: sessionCount > 0 ? wall / Double(sessionCount) : 0,
            uniqueDays: days.count,
            booksFinished: finishedIDs.count,
            booksStarted: booksStarted,
            currentStreak: streak.current,
            longestStreak: streak.longest,
            perBook: grouped.values.sorted { $0.wallDuration > $1.wallDuration },
            heatmap: heatmap(sessions: inPeriod, period: period, now: now, calendar: calendar)
        )
    }

    nonisolated static func formatCompact(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds > 0 && minutes < 10 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    /// VoiceOver duration. 72 minutes → "1 hour 12 minutes". Under one minute uses seconds.
    nonisolated static func formatSpoken(_ duration: TimeInterval, locale: Locale = .current) -> String {
        let total = max(0, Int64(duration.rounded()))
        let style: Duration.UnitsFormatStyle
        if total < 60 {
            style = .units(allowed: [.seconds], width: .wide, zeroValueUnits: .show(length: 1))
        } else {
            style = .units(allowed: [.hours, .minutes], width: .wide, zeroValueUnits: .hide)
        }
        let raw = Duration.seconds(total).formatted(style.locale(locale))
        return raw.replacingOccurrences(of: ", ", with: " ")
    }

    /// Cell label: weekday, month, day, then spoken duration. Year only when `day` is not in `now`'s year.
    nonisolated static func heatmapSpokenLabel(
        day: Date,
        wallDuration: TimeInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let locale = calendar.locale ?? .current
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
            .month(.wide)
            .day()
        if calendar.component(.year, from: day) != calendar.component(.year, from: now) {
            style = style.year()
        }
        let dateText = day.formatted(style)
        if wallDuration <= 0 {
            return "\(dateText), no listening"
        }
        return "\(dateText), \(formatSpoken(wallDuration, locale: locale))"
    }

    nonisolated static func showsMonthTicks(for period: StatsPeriod) -> Bool {
        period == .year || period == .all
    }

    nonisolated static func monthTicks(days: [HeatmapDay], calendar: Calendar) -> [HeatmapMonthTick] {
        let symbols = calendar.veryShortMonthSymbols
        var ticks: [HeatmapMonthTick] = []
        var seenWeeks = Set<Int>()
        for day in days.sorted(by: { $0.day < $1.day }) {
            guard calendar.component(.day, from: day.day) == 1 else { continue }
            guard !seenWeeks.contains(day.weekIndex) else { continue }
            let month = calendar.component(.month, from: day.day)
            let index = month - 1
            guard symbols.indices.contains(index) else { continue }
            seenWeeks.insert(day.weekIndex)
            ticks.append(HeatmapMonthTick(weekIndex: day.weekIndex, letter: symbols[index]))
        }
        return ticks
    }
}

struct HeatmapMonthTick: Equatable, Sendable {
    var weekIndex: Int
    var letter: String
}
