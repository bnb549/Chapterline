import SwiftUI

struct DaySessionsSheet: View {
    let day: Date
    let wallDuration: TimeInterval
    let sessions: [SessionRow]
    let usesTrueBlack: Bool
    let onOpenBook: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if sessions.isEmpty {
                    Text("No sessions this day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.chromeBackground(oled: usesTrueBlack))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fullDate)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(ListeningStatsMath.formatCompact(wallDuration))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fullDate), \(ListeningStatsMath.formatSpoken(wallDuration))")
    }

    private var fullDate: String {
        day.formatted(Date.FormatStyle().weekday(.wide).month(.wide).day().year())
    }

    private func sessionRow(_ session: SessionRow) -> some View {
        Button {
            if session.bookExists {
                onOpenBook(session.bookID)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = sessionSubtitle(session) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(ListeningStatsMath.formatCompact(session.wallDuration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if session.bookExists {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.elevated.opacity(usesTrueBlack ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.bookExists)
        .accessibilityLabel(sessionAccessibility(session))
        .accessibilityHint(session.bookExists ? "Opens the book" : "Book is no longer in the library")
    }

    private func sessionSubtitle(_ session: SessionRow) -> String? {
        let chapter = session.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.bookExists {
            return chapter.isEmpty ? nil : chapter
        }
        if chapter.isEmpty {
            return "Deleted"
        }
        return "\(chapter) · Deleted"
    }

    private func sessionAccessibility(_ session: SessionRow) -> String {
        let time = ListeningStatsMath.formatCompact(session.wallDuration)
        let rate = String(format: "%.1f times", session.rate)
        let when = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        let missing = session.bookExists ? "" : ", book deleted"
        return "\(session.title), \(time), \(rate), \(when)\(missing)"
    }
}

#if DEBUG
#Preview("Day sessions") {
    let bookID = UUID()
    let missingID = UUID()
    let day = Calendar.current.startOfDay(for: Date())
    let rows = [
        SessionRow(
            id: UUID(),
            bookID: bookID,
            title: "Dune",
            author: "Frank Herbert",
            startedAt: day.addingTimeInterval(7 * 3600),
            wallDuration: 42 * 60,
            rate: 1.2,
            chapterTitle: "Muad'Dib",
            bookExists: true
        ),
        SessionRow(
            id: UUID(),
            bookID: missingID,
            title: "Pride and Prejudice",
            author: "Jane Austen",
            startedAt: day.addingTimeInterval(18 * 3600),
            wallDuration: 30 * 60,
            rate: 1.0,
            chapterTitle: "Chapter 2",
            bookExists: false
        )
    ]
    return DaySessionsSheet(
        day: day,
        wallDuration: 72 * 60,
        sessions: rows,
        usesTrueBlack: false,
        onOpenBook: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Empty day") {
    DaySessionsSheet(
        day: Calendar.current.startOfDay(for: Date()),
        wallDuration: 0,
        sessions: [],
        usesTrueBlack: true,
        onOpenBook: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
