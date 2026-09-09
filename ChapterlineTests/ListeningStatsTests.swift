import SwiftData
import XCTest
@testable import Chapterline

final class ListeningStatsMathTests: XCTestCase {
    func testShortWallIsDiscarded() {
        XCTAssertFalse(ListeningStatsMath.shouldCount(wallDuration: 14.9))
        XCTAssertTrue(ListeningStatsMath.shouldCount(wallDuration: 15))
        XCTAssertTrue(ListeningStatsMath.shouldCount(wallDuration: 20))
    }

    func testContentEqualsWallTimesRate() {
        XCTAssertEqual(ListeningStatsMath.contentDuration(wall: 60, rate: 1.5), 90, accuracy: 0.001)
        XCTAssertEqual(ListeningStatsMath.contentDuration(wall: 60, rate: 1), 60, accuracy: 0.001)
        XCTAssertEqual(ListeningStatsMath.contentDuration(wall: 60, rate: 0), 60, accuracy: 0.001)
    }

    func testTimeSavedAtOnePointFive() {
        let wall: TimeInterval = 60
        let content = ListeningStatsMath.contentDuration(wall: wall, rate: 1.5)
        XCTAssertEqual(ListeningStatsMath.timeSaved(wall: wall, content: content), 30, accuracy: 0.001)
        XCTAssertEqual(ListeningStatsMath.timeSaved(wall: 90, content: 60), 0, accuracy: 0.001)
    }

    func testStreakUsesLocalCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // 07:00 UTC on 9 Sep 2026 is midnight PDT. 06:00 UTC is still 8 Sep locally.
        let lateEighth = date(2026, 9, 9, 6, 0, 0, calendar: Calendar(identifier: .gregorian).utc)
        let earlyNinth = date(2026, 9, 9, 8, 0, 0, calendar: Calendar(identifier: .gregorian).utc)
        let now = date(2026, 9, 9, 18, 0, 0, calendar: Calendar(identifier: .gregorian).utc)

        XCTAssertEqual(calendar.startOfDay(for: lateEighth), calendar.startOfDay(for: date(2026, 9, 8, 12, 0, 0, calendar: calendar)))
        XCTAssertEqual(calendar.startOfDay(for: earlyNinth), calendar.startOfDay(for: now))

        let days = ListeningStatsMath.activityDays(
            sessions: [
                input(startedAt: lateEighth),
                input(startedAt: earlyNinth)
            ],
            calendar: calendar
        )
        XCTAssertEqual(days.count, 2)

        let streak = ListeningStatsMath.streaks(days: days, now: now, calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.longest, 2)
    }

    func testCurrentStreakBreaksWithoutYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 9, 9, 12, 0, 0, calendar: calendar)
        let twoDaysAgo = date(2026, 9, 7, 12, 0, 0, calendar: calendar)
        let days: Set<Date> = [calendar.startOfDay(for: twoDaysAgo)]
        let streak = ListeningStatsMath.streaks(days: days, now: now, calendar: calendar)
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.longest, 1)
    }

    func testCurrentStreakAllowsEmptyToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 9, 9, 12, 0, 0, calendar: calendar)
        let yesterday = date(2026, 9, 8, 12, 0, 0, calendar: calendar)
        let twoDaysAgo = date(2026, 9, 7, 12, 0, 0, calendar: calendar)
        let days: Set<Date> = [
            calendar.startOfDay(for: yesterday),
            calendar.startOfDay(for: twoDaysAgo)
        ]
        let streak = ListeningStatsMath.streaks(days: days, now: now, calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.longest, 2)
    }

    private func input(startedAt: Date) -> ListeningStatsInput {
        ListeningStatsInput(
            bookID: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            wallDuration: 60,
            contentDuration: 60,
            endReason: .pause,
            counted: true
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }
}

private extension Calendar {
    var utc: Calendar {
        var calendar = self
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

final class ListeningStatsStoreTests: XCTestCase {
    func testSessionsShorterThan15SecondsAreDiscarded() {
        let store = makeStore(tracking: true)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 10, rate: 1), now: t)
        store.ingest(snap(bookID: bookID, playing: false, position: 20, rate: 1, stopReason: .pause), now: t.addingTimeInterval(10))
        XCTAssertFalse(store.hasOpenSession)
        XCTAssertEqual(store.allTimeSessionCount, 0)
        XCTAssertEqual(store.summary.sessionCount, 0)
    }

    func testPlayThenPauseRecordsOneSession() {
        let store = makeStore(tracking: true)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 10, rate: 1), now: t)
        store.ingest(snap(bookID: bookID, playing: false, position: 40, rate: 1, stopReason: .pause), now: t.addingTimeInterval(30))
        XCTAssertEqual(store.allTimeSessionCount, 1)
        XCTAssertEqual(store.summary.wallDuration, 30, accuracy: 0.01)
        XCTAssertEqual(store.summary.contentDuration, 30, accuracy: 0.01)
        XCTAssertEqual(store.summary.sessionCount, 1)
    }

    func testSeekDoesNotInflateWall() {
        let store = makeStore(tracking: true)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 0, rate: 1), now: t)
        store.ingest(snap(bookID: bookID, playing: true, position: 3_600, rate: 1), now: t.addingTimeInterval(20))
        store.ingest(snap(bookID: bookID, playing: false, position: 3_600, rate: 1, stopReason: .pause), now: t.addingTimeInterval(60))
        XCTAssertEqual(store.summary.wallDuration, 60, accuracy: 0.01)
        XCTAssertEqual(store.summary.contentDuration, 60, accuracy: 0.01)
        XCTAssertEqual(store.recentSessions.first?.wallDuration ?? 0, 60, accuracy: 0.01)
    }

    func testContentMatchesWallTimesRateAndSavesThirtySeconds() {
        let store = makeStore(tracking: true)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 100, rate: 1.5), now: t)
        store.ingest(snap(bookID: bookID, playing: false, position: 190, rate: 1.5, stopReason: .pause), now: t.addingTimeInterval(60))
        XCTAssertEqual(store.summary.wallDuration, 60, accuracy: 0.01)
        XCTAssertEqual(store.summary.contentDuration, 90, accuracy: 0.01)
        XCTAssertEqual(store.summary.timeSaved, 30, accuracy: 0.01)
    }

    func testTrackingOffCreatesNoSessions() {
        let store = makeStore(tracking: false)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 0, rate: 1), now: t)
        XCTAssertFalse(store.hasOpenSession)
        store.ingest(snap(bookID: bookID, playing: false, position: 80, rate: 1, stopReason: .pause), now: t.addingTimeInterval(80))
        XCTAssertEqual(store.allTimeSessionCount, 0)
        XCTAssertEqual(store.summary.wallDuration, 0, accuracy: 0.01)
    }

    func testDeletingBookKeepsSessions() {
        let container = Persistence.inMemory()
        let settings = makeSettings(tracking: true)
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        stats.period = .all

        let book = Book(title: "Dune", author: "Frank Herbert", sourceFilename: "dune.m4b", duration: 10_000)
        let insertContext = ModelContext(container)
        insertContext.insert(book)
        try? insertContext.save()
        library.refresh()

        let bookID = book.id
        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: bookID, playing: true, position: 0, rate: 1.2, title: "Dune"), now: t)
        stats.ingest(snap(bookID: bookID, playing: false, position: 80, rate: 1.2, title: "Dune", stopReason: .pause), now: t.addingTimeInterval(80))
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)

        guard let live = library.book(id: bookID) else {
            XCTFail("Book should exist before delete")
            return
        }
        library.delete(live)
        XCTAssertNil(library.book(id: bookID))

        stats.refresh()
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)
        XCTAssertEqual(stats.recentSessions.first?.title, "Dune")
        XCTAssertFalse(stats.recentSessions.first?.bookExists ?? true)
    }

    func testRateChangeSplitsSession() {
        let store = makeStore(tracking: true)
        let bookID = UUID()
        let t = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(snap(bookID: bookID, playing: true, position: 0, rate: 1), now: t)
        store.ingest(snap(bookID: bookID, playing: true, position: 40, rate: 1.5), now: t.addingTimeInterval(40))
        store.ingest(snap(bookID: bookID, playing: false, position: 70, rate: 1.5, stopReason: .pause), now: t.addingTimeInterval(100))
        XCTAssertEqual(store.summary.sessionCount, 2)
        XCTAssertEqual(store.summary.wallDuration, 100, accuracy: 0.01)
        XCTAssertEqual(store.summary.contentDuration, 40 + 60 * 1.5, accuracy: 0.01)
    }

    private func makeStore(tracking: Bool) -> ListeningStatsStore {
        let store = ListeningStatsStore(container: Persistence.inMemory(), settings: makeSettings(tracking: tracking))
        store.period = .all
        return store
    }

    private func makeSettings(tracking: Bool) -> SettingsStore {
        let suite = "chapterline.stats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.trackListeningStats = tracking
        return settings
    }

    private func snap(
        bookID: UUID,
        playing: Bool,
        position: TimeInterval,
        rate: Double,
        duration: TimeInterval = 10_000,
        title: String = "Dune",
        stopReason: SessionEndReason? = nil
    ) -> PlayerSnapshot {
        var snapshot = PlayerSnapshot.empty
        snapshot.bookID = bookID
        snapshot.title = title
        snapshot.author = "Frank Herbert"
        snapshot.chapterTitle = "Chapter 1"
        snapshot.position = position
        snapshot.duration = duration
        snapshot.rate = rate
        snapshot.isPlaying = playing
        snapshot.stopReason = stopReason
        return snapshot
    }
}
