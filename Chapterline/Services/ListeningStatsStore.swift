import Foundation
import Observation
import SwiftData

struct SessionRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var bookID: UUID
    var title: String
    var author: String
    var startedAt: Date
    var wallDuration: TimeInterval
    var rate: Double
    var chapterTitle: String
    var bookExists: Bool
}

struct ListeningStatsExportPayload: Codable, Sendable {
    var exportedAt: Date
    var totals: Totals
    var perBook: [BookExport]
    var sessions: [SessionExport]

    struct Totals: Codable, Sendable {
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
    }

    struct BookExport: Codable, Sendable {
        var bookID: UUID
        var title: String
        var author: String
        var wallDuration: TimeInterval
        var contentDuration: TimeInterval
        var sessionCount: Int
    }

    struct SessionExport: Codable, Sendable {
        var id: UUID
        var bookID: UUID
        var bookTitle: String
        var author: String
        var narrator: String?
        var startedAt: Date
        var endedAt: Date
        var wallDuration: TimeInterval
        var contentDuration: TimeInterval
        var rate: Double
        var startPosition: TimeInterval
        var endPosition: TimeInterval
        var chapterTitle: String
        var endReason: String
        var counted: Bool
    }
}

@Observable
final class ListeningStatsStore {
    var period: StatsPeriod = .today {
        didSet { refresh() }
    }
    var summary = ListeningReduction.empty
    var recentSessions: [SessionRow] = []
    var hasOpenSession: Bool { open != nil }

    let container: ModelContainer
    private let context: ModelContext
    private let settings: SettingsStore
    private var open: OpenSession?

    private struct OpenSession {
        var bookID: UUID
        var bookTitle: String
        var author: String
        var narrator: String?
        var startedAt: Date
        var rate: Double
        var startPosition: TimeInterval
        var chapterTitle: String
        var identityKey: String?
    }

    init(container: ModelContainer, settings: SettingsStore = .shared) {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = true
        self.settings = settings
        refresh()
    }

    func ingest(_ snap: PlayerSnapshot, now: Date = Date()) {
        guard settings.trackListeningStats else {
            discardOpenSession()
            return
        }

        if let open {
            if snap.bookID != open.bookID {
                closeOpenSession(reason: .skipAway, from: snap, now: now)
            } else if snap.isPlaying, abs(snap.rate - open.rate) > 0.049 {
                closeOpenSession(reason: .unknown, from: snap, now: now)
            } else if !snap.isPlaying {
                closeOpenSession(reason: resolvedStopReason(snap), from: snap, now: now)
                return
            } else {
                return
            }
        }

        if snap.isPlaying, snap.bookID != nil {
            openSession(from: snap, now: now)
        }
    }

    func closeOpenSession(
        reason: SessionEndReason,
        from snap: PlayerSnapshot? = nil,
        now: Date = Date()
    ) {
        guard let open else { return }
        let wall = max(0, now.timeIntervalSince(open.startedAt))
        let endPosition = snap?.position ?? open.startPosition
        let chapterTitle = (snap?.chapterTitle.isEmpty == false) ? (snap?.chapterTitle ?? open.chapterTitle) : open.chapterTitle
        self.open = nil

        guard ListeningStatsMath.shouldCount(wallDuration: wall) else { return }

        let session = ListeningSession(
            bookID: open.bookID,
            bookTitle: open.bookTitle,
            author: open.author,
            narrator: open.narrator,
            startedAt: open.startedAt,
            endedAt: now,
            wallDuration: wall,
            contentDuration: ListeningStatsMath.contentDuration(wall: wall, rate: open.rate),
            rate: open.rate,
            startPosition: open.startPosition,
            endPosition: max(0, endPosition),
            chapterTitle: chapterTitle,
            endReason: reason,
            counted: true,
            identityKey: open.identityKey
        )
        context.insert(session)
        save()
        refresh()
    }

    func discardOpenSession() {
        open = nil
    }

    func deleteAll() {
        discardOpenSession()
        let descriptor = FetchDescriptor<ListeningSession>()
        let sessions = (try? context.fetch(descriptor)) ?? []
        for session in sessions {
            context.delete(session)
        }
        save()
        refresh()
    }

    func refresh() {
        let now = Date()
        let calendar = Calendar.current
        let sessions = fetchSessions()
        let inputs = sessions.map {
            ListeningStatsInput(
                bookID: $0.bookID,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                wallDuration: $0.wallDuration,
                contentDuration: $0.contentDuration,
                endReason: $0.endReason,
                counted: $0.counted
            )
        }
        var titles: [UUID: (title: String, author: String)] = [:]
        for session in sessions {
            titles[session.bookID] = (session.bookTitle, session.author)
        }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        var didBackfill = false
        for book in books {
            titles[book.id] = (book.title, book.author)
            if let key = book.identityKey {
                for session in sessions where session.bookID == book.id && session.identityKey == nil {
                    session.identityKey = key
                    didBackfill = true
                }
            }
        }
        if didBackfill {
            save()
        }
        let finished = books.compactMap { book -> (bookID: UUID, at: Date)? in
            guard let finishedAt = book.finishedAt else { return nil }
            return (book.id, finishedAt)
        }
        let existingIDs = Set(books.map(\.id))
        summary = ListeningStatsMath.reduce(
            sessions: inputs,
            titles: titles,
            finished: finished,
            period: period,
            now: now,
            calendar: calendar
        )
        recentSessions = sessions.prefix(30).map { session in
            makeSessionRow(session, existingIDs: existingIDs)
        }
    }

    func sessionsStarted(
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SessionRow] {
        _ = now
        let target = calendar.startOfDay(for: day)
        let sessions = fetchSessions()
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let existingIDs = Set(books.map(\.id))
        return sessions
            .filter { calendar.startOfDay(for: $0.startedAt) == target }
            .sorted { $0.startedAt < $1.startedAt }
            .map { makeSessionRow($0, existingIDs: existingIDs) }
    }

    func exportJSON() throws -> Data {
        let calendar = Calendar.current
        let now = Date()
        let sessions = fetchSessions()
        let inputs = sessions.map {
            ListeningStatsInput(
                bookID: $0.bookID,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                wallDuration: $0.wallDuration,
                contentDuration: $0.contentDuration,
                endReason: $0.endReason,
                counted: $0.counted
            )
        }
        var titles: [UUID: (title: String, author: String)] = [:]
        for session in sessions {
            titles[session.bookID] = (session.bookTitle, session.author)
        }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let finished = books.compactMap { book -> (bookID: UUID, at: Date)? in
            guard let finishedAt = book.finishedAt else { return nil }
            return (book.id, finishedAt)
        }
        let allTime = ListeningStatsMath.reduce(
            sessions: inputs,
            titles: titles,
            finished: finished,
            period: .all,
            now: now,
            calendar: calendar
        )
        let payload = ListeningStatsExportPayload(
            exportedAt: now,
            totals: .init(
                wallDuration: allTime.wallDuration,
                contentDuration: allTime.contentDuration,
                timeSaved: allTime.timeSaved,
                sessionCount: allTime.sessionCount,
                averageLength: allTime.averageLength,
                uniqueDays: allTime.uniqueDays,
                booksFinished: allTime.booksFinished,
                booksStarted: allTime.booksStarted,
                currentStreak: allTime.currentStreak,
                longestStreak: allTime.longestStreak
            ),
            perBook: allTime.perBook.map {
                .init(
                    bookID: $0.bookID,
                    title: $0.title,
                    author: $0.author,
                    wallDuration: $0.wallDuration,
                    contentDuration: $0.contentDuration,
                    sessionCount: $0.sessionCount
                )
            },
            sessions: sessions.map {
                .init(
                    id: $0.id,
                    bookID: $0.bookID,
                    bookTitle: $0.bookTitle,
                    author: $0.author,
                    narrator: $0.narrator,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    wallDuration: $0.wallDuration,
                    contentDuration: $0.contentDuration,
                    rate: $0.rate,
                    startPosition: $0.startPosition,
                    endPosition: $0.endPosition,
                    chapterTitle: $0.chapterTitle,
                    endReason: $0.endReason.rawValue,
                    counted: $0.counted
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    func exportFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chapterline-stats.json")
        let data = (try? exportJSON()) ?? Data("{}".utf8)
        try? data.write(to: url, options: .atomic)
        return url
    }

    var allTimeSessionCount: Int {
        fetchSessions().count
    }

    private func openSession(from snap: PlayerSnapshot, now: Date) {
        guard let bookID = snap.bookID else { return }
        open = OpenSession(
            bookID: bookID,
            bookTitle: snap.title,
            author: snap.author,
            narrator: snap.narrator,
            startedAt: now,
            rate: snap.rate > 0 ? snap.rate : 1,
            startPosition: snap.position,
            chapterTitle: snap.chapterTitle,
            identityKey: identityKey(for: bookID)
        )
    }

    private func resolvedStopReason(_ snap: PlayerSnapshot) -> SessionEndReason {
        let finished = snap.duration > 0 && snap.position >= snap.duration - 1
        if finished { return .finished }
        return snap.stopReason ?? .pause
    }

    private func identityKey(for bookID: UUID) -> String? {
        var descriptor = FetchDescriptor<Book>()
        descriptor.predicate = #Predicate { $0.id == bookID }
        return (try? context.fetch(descriptor))?.first?.identityKey
    }

    private func makeSessionRow(_ session: ListeningSession, existingIDs: Set<UUID>) -> SessionRow {
        SessionRow(
            id: session.id,
            bookID: session.bookID,
            title: session.bookTitle,
            author: session.author,
            startedAt: session.startedAt,
            wallDuration: session.wallDuration,
            rate: session.rate,
            chapterTitle: session.chapterTitle,
            bookExists: existingIDs.contains(session.bookID)
        )
    }

    private func fetchSessions() -> [ListeningSession] {
        var descriptor = FetchDescriptor<ListeningSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.predicate = #Predicate { $0.counted == true }
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        try? context.save()
    }
}
