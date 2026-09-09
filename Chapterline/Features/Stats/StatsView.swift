import Charts
import SwiftUI

struct StatsView: View {
    @Environment(ListeningStatsStore.self) private var stats
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerController.self) private var player

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.pageBackground(oled: settings.usesTrueBlack).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        periodControl
                        if !settings.trackListeningStats {
                            trackingOffBanner
                        }
                        headline
                        streakAndFinished
                        heatmap
                        recentSessions
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(settings.usesTrueBlack ? Color.black : Color.clear, for: .navigationBar)
            .toolbarBackground(settings.usesTrueBlack ? .visible : .automatic, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let book = library.book(id: id) {
                    BookPlayerView(bookID: id)
                        .onAppear {
                            Task { await player.load(book: book) }
                        }
                } else {
                    ContentUnavailableView("Book missing", systemImage: "book.closed")
                }
            }
            .onAppear { stats.refresh() }
            .onChange(of: library.books.count) { _, _ in
                stats.refresh()
            }
        }
    }

    private var periodControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StatsPeriod.allCases) { period in
                    let selected = stats.period == period
                    Button {
                        stats.period = period
                    } label: {
                        Text(period.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                selected ? Color.accentColor.opacity(0.28) : Theme.chromeBackground(oled: settings.usesTrueBlack),
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? Color.accentColor : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(period.accessibilityLabel)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stats period")
    }

    private var trackingOffBanner: some View {
        Text("Tracking is off. Hours stay on this device when you turn it back on in Settings.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Listening stats tracking is off")
    }

    private var headline: some View {
        let summary = stats.summary
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ListeningStatsMath.formatCompact(summary.wallDuration))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Listened")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Listened \(ListeningStatsMath.formatCompact(summary.wallDuration))")

            HStack(spacing: 10) {
                metricCard(
                    value: ListeningStatsMath.formatCompact(summary.contentDuration),
                    label: "Heard",
                    accessibility: "Heard \(ListeningStatsMath.formatCompact(summary.contentDuration)) of content"
                )
                metricCard(
                    value: ListeningStatsMath.formatCompact(summary.timeSaved),
                    label: "Saved",
                    accessibility: "Saved \(ListeningStatsMath.formatCompact(summary.timeSaved)) by listening faster"
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricCard(value: String, label: String, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.elevated.opacity(settings.usesTrueBlack ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var streakAndFinished: some View {
        let summary = stats.summary
        return HStack(spacing: 10) {
            chip(
                title: streakTitle(summary),
                systemImage: "flame.fill",
                accessibility: "Current streak \(summary.currentStreak) days, longest \(summary.longestStreak)"
            )
            chip(
                title: summary.booksFinished == 1 ? "1 finished" : "\(summary.booksFinished) finished",
                systemImage: "checkmark.circle.fill",
                accessibility: "\(summary.booksFinished) books finished"
            )
        }
    }

    private func streakTitle(_ summary: ListeningReduction) -> String {
        if summary.currentStreak == 0 {
            return "No streak"
        }
        var title = "\(summary.currentStreak)-day streak"
        if summary.longestStreak > summary.currentStreak {
            title += " · Best \(summary.longestStreak)"
        }
        return title
    }

    private func chip(title: String, systemImage: String, accessibility: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: Capsule())
            .foregroundStyle(Theme.textPrimary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)
    }

    private var heatmap: some View {
        let days = stats.summary.heatmap
        return VStack(alignment: .leading, spacing: 10) {
            Text("Heatmap")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if days.isEmpty {
                Text("Play for a bit and days will fill in here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Chart(days) { day in
                    RectangleMark(
                        x: .value("Week", day.weekIndex),
                        y: .value("Weekday", day.weekday)
                    )
                    .foregroundStyle(heatmapColor(for: day.wallDuration))
                    .cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 2, 4, 6]) { value in
                        AxisValueLabel {
                            if let weekday = value.as(Int.self) {
                                Text(weekdayLetter(weekday))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartYScale(domain: -0.5...6.5)
                .frame(height: 148)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Listening heatmap")
                .accessibilityValue(heatmapValue(days))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent sessions")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if stats.recentSessions.isEmpty {
                Text("Sessions longer than 15 seconds show up here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(stats.recentSessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: SessionRow) -> some View {
        Button {
            if session.bookExists {
                path.append(session.bookID)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(sessionSubtitle(session))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if session.bookExists {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.bookExists)
        .accessibilityLabel(sessionAccessibility(session))
        .accessibilityHint(session.bookExists ? "Opens the book" : "Book is no longer in the library")
    }

    private func sessionSubtitle(_ session: SessionRow) -> String {
        let time = ListeningStatsMath.formatCompact(session.wallDuration)
        let rate = String(format: "%.1f×", session.rate)
        let when = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        if session.bookExists {
            return "\(time) · \(rate) · \(when)"
        }
        return "\(time) · \(rate) · \(when) · Deleted"
    }

    private func sessionAccessibility(_ session: SessionRow) -> String {
        let time = ListeningStatsMath.formatCompact(session.wallDuration)
        let rate = String(format: "%.1f times", session.rate)
        let when = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        let missing = session.bookExists ? "" : ", book deleted"
        return "\(session.title), \(time), \(rate), \(when)\(missing)"
    }

    private func heatmapColor(for wall: TimeInterval) -> Color {
        if wall <= 0 { return Theme.fill }
        let minutes = wall / 60
        if minutes < 15 { return Color.accentColor.opacity(0.28) }
        if minutes < 45 { return Color.accentColor.opacity(0.5) }
        if minutes < 90 { return Color.accentColor.opacity(0.75) }
        return Color.accentColor
    }

    private func weekdayLetter(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = (weekday + Calendar.current.firstWeekday - 1 + 7) % 7
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private func heatmapValue(_ days: [HeatmapDay]) -> String {
        let active = days.filter { $0.wallDuration > 0 }.count
        return "\(active) days with listening"
    }
}

#if DEBUG
#Preview("Stats") {
    let library = PreviewSupport.library()
    let stats = ListeningStatsStore(container: library.container)
    return StatsView()
        .environment(library)
        .environment(stats)
        .environment(SettingsStore.shared)
        .environment(PlayerController())
        .preferredColorScheme(.dark)
}
#endif
