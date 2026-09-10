import SwiftData
import XCTest
@testable import Chapterline

final class BookIdentityMathTests: XCTestCase {
    func testIdentityKeyIsStableAndIgnoresTitleCaseAndWhitespace() {
        let left = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000.4,
            totalByteSize: 4_096,
            filenames: ["Dune.m4b"]
        )
        let right = BookIdentityMath.fingerprint(
            title: " dune ",
            author: "Frank Herbert",
            duration: 10_000.4,
            totalByteSize: 4_096,
            filenames: ["Dune.m4b"]
        )
        XCTAssertEqual(left.identityKey, right.identityKey)
        XCTAssertEqual(left.identityKey, BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000.4,
            totalByteSize: 4_096,
            filenames: ["Dune.m4b"]
        ).identityKey)
    }

    func testUnknownAuthorNormalizesToEmptyInKey() {
        let tagged = BookIdentityMath.identityKey(
            title: "Dune",
            author: "Frank Herbert",
            duration: 100,
            totalByteSize: 50,
            fileCount: 1,
            sourceSignature: "dune.m4b"
        )
        let unknown = BookIdentityMath.identityKey(
            title: "Dune",
            author: "Unknown Author",
            duration: 100,
            totalByteSize: 50,
            fileCount: 1,
            sourceSignature: "dune.m4b"
        )
        XCTAssertNotEqual(tagged, unknown)
        XCTAssertEqual(
            BookIdentityMath.identityKey(
                title: "Dune",
                author: "",
                duration: 100,
                totalByteSize: 50,
                fileCount: 1,
                sourceSignature: "dune.m4b"
            ),
            unknown
        )
    }

    func testCombinePrefixIsStrippedFromSignature() {
        let combined = BookIdentityMath.sourceSignature(filenames: ["000-ch1.mp3", "001-ch2.mp3"])
        let originals = BookIdentityMath.sourceSignature(filenames: ["ch1.mp3", "ch2.mp3"])
        XCTAssertEqual(combined, originals)
        XCTAssertEqual(BookIdentityMath.stripCombinePrefix("012-intro.m4b"), "intro.m4b")
        XCTAssertEqual(BookIdentityMath.stripCombinePrefix("dune.m4b"), "dune.m4b")
    }

    func testCombinedImportMatchesLaterCombinedImport() {
        let first = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 200,
            totalByteSize: 800,
            filenames: ["000-ch1.mp3", "001-ch2.mp3"]
        )
        let second = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 200,
            totalByteSize: 800,
            filenames: ["000-ch1.mp3", "001-ch2.mp3"]
        )
        XCTAssertEqual(first.identityKey, second.identityKey)

        let candidate = candidate(
            bookID: UUID(),
            fingerprint: first,
            sessionCount: 3
        )
        let resolved = BookIdentityMath.resolve(
            fingerprint: second,
            liveBookIDs: [],
            identities: [candidate],
            orphans: [],
            stagingID: UUID()
        )
        XCTAssertTrue(resolved.reused)
        XCTAssertEqual(resolved.bookID, candidate.bookID)
    }

    func testCombinedDoesNotMatchSingleChapter() {
        let combined = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 200,
            totalByteSize: 800,
            filenames: ["000-ch1.mp3", "001-ch2.mp3"]
        )
        let single = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 100,
            totalByteSize: 400,
            filenames: ["ch1.mp3"]
        )
        XCTAssertNotEqual(combined.identityKey, single.identityKey)

        let resolved = BookIdentityMath.resolve(
            fingerprint: single,
            liveBookIDs: [],
            identities: [candidate(bookID: UUID(), fingerprint: combined, sessionCount: 4)],
            orphans: [],
            stagingID: UUID()
        )
        XCTAssertFalse(resolved.reused)
    }

    func testGenericTitleDifferentDurationGetsNewID() {
        let audioA = BookIdentityMath.fingerprint(
            title: "Audio",
            author: "Unknown Author",
            duration: 100,
            totalByteSize: 1_000,
            filenames: ["audio.m4b"]
        )
        let audioB = BookIdentityMath.fingerprint(
            title: "Audio",
            author: "Unknown Author",
            duration: 500,
            totalByteSize: 9_000,
            filenames: ["audio.m4b"]
        )
        let staging = UUID()
        let resolved = BookIdentityMath.resolve(
            fingerprint: audioB,
            liveBookIDs: [],
            identities: [candidate(bookID: UUID(), fingerprint: audioA, sessionCount: 2)],
            orphans: [],
            stagingID: staging
        )
        XCTAssertFalse(resolved.reused)
        XCTAssertEqual(resolved.bookID, staging)
    }

    func testUnknownAuthorMatchesTaggedAuthorWhenFilenameIsSpecific() {
        let tagged = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
        let unknown = candidate(
            bookID: UUID(),
            fingerprint: BookIdentityMath.fingerprint(
                title: "Dune",
                author: "Unknown Author",
                duration: 10_000,
                totalByteSize: 4_096,
                filenames: ["dune.m4b"]
            ),
            sessionCount: 1
        )
        XCTAssertTrue(BookIdentityMath.fuzzyMatch(incoming: tagged, candidate: unknown))
        let resolved = BookIdentityMath.resolve(
            fingerprint: tagged,
            liveBookIDs: [],
            identities: [unknown],
            orphans: [],
            stagingID: UUID()
        )
        XCTAssertTrue(resolved.reused)
        XCTAssertEqual(resolved.bookID, unknown.bookID)
    }

    func testUnknownAuthorDoesNotMatchWhenFilenameIsGeneric() {
        let tagged = BookIdentityMath.fingerprint(
            title: "Audio",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["audio.m4b"]
        )
        let unknown = candidate(
            bookID: UUID(),
            fingerprint: BookIdentityMath.fingerprint(
                title: "Audio",
                author: "Unknown Author",
                duration: 10_000,
                totalByteSize: 4_096,
                filenames: ["audio.m4b"]
            ),
            sessionCount: 1
        )
        XCTAssertFalse(BookIdentityMath.fuzzyMatch(incoming: tagged, candidate: unknown))
        let staging = UUID()
        let resolved = BookIdentityMath.resolve(
            fingerprint: tagged,
            liveBookIDs: [],
            identities: [unknown],
            orphans: [],
            stagingID: staging
        )
        XCTAssertFalse(resolved.reused)
        XCTAssertEqual(resolved.bookID, staging)
    }

    func testLiveBookIsNotReused() {
        let fingerprint = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
        let liveID = UUID()
        let staging = UUID()
        let resolved = BookIdentityMath.resolve(
            fingerprint: fingerprint,
            liveBookIDs: [liveID],
            identities: [candidate(bookID: liveID, fingerprint: fingerprint, sessionCount: 5)],
            orphans: [],
            stagingID: staging
        )
        XCTAssertFalse(resolved.reused)
        XCTAssertEqual(resolved.bookID, staging)
    }

    func testTwoDeletedBooksWithIdenticalKeysDoNotMerge() {
        let fingerprint = BookIdentityMath.fingerprint(
            title: "Untitled",
            author: "Unknown Author",
            duration: 60,
            totalByteSize: 100,
            filenames: ["audio.m4b"]
        )
        let first = candidate(bookID: UUID(), fingerprint: fingerprint, sessionCount: 3, lastSeenAt: Date(timeIntervalSince1970: 100))
        let second = candidate(bookID: UUID(), fingerprint: fingerprint, sessionCount: 1, lastSeenAt: Date(timeIntervalSince1970: 200))
        let staging = UUID()
        let resolved = BookIdentityMath.resolve(
            fingerprint: fingerprint,
            liveBookIDs: [],
            identities: [first, second],
            orphans: [],
            stagingID: staging
        )
        XCTAssertFalse(resolved.reused)
        XCTAssertEqual(resolved.bookID, staging)
    }

    func testProbeHashChangesKeyButOldRowsStillFuzzyMatch() {
        let withoutProbe = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
        let withProbe = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"],
            probeHash: "abc123"
        )
        XCTAssertNotEqual(withoutProbe.identityKey, withProbe.identityKey)

        let oldRow = candidate(bookID: UUID(), fingerprint: withoutProbe, sessionCount: 2)
        let resolved = BookIdentityMath.resolve(
            fingerprint: withProbe,
            liveBookIDs: [],
            identities: [oldRow],
            orphans: [],
            stagingID: UUID()
        )
        XCTAssertTrue(resolved.reused)
        XCTAssertEqual(resolved.bookID, oldRow.bookID)
    }

    func testDifferentProbesDoNotFuzzyMatch() {
        let left = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"],
            probeHash: "aaa"
        )
        let right = candidate(
            bookID: UUID(),
            fingerprint: BookIdentityMath.fingerprint(
                title: "Dune",
                author: "Frank Herbert",
                duration: 10_000,
                totalByteSize: 4_096,
                filenames: ["dune.m4b"],
                probeHash: "bbb"
            ),
            sessionCount: 2
        )
        XCTAssertFalse(BookIdentityMath.fuzzyMatch(incoming: left, candidate: right))
    }

    func testEmptyTitleMatchesOnFilenameStem() {
        let incoming = BookIdentityMath.fingerprint(
            title: "",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
        let stored = candidate(
            bookID: UUID(),
            fingerprint: BookIdentityMath.fingerprint(
                title: "Dune",
                author: "Frank Herbert",
                duration: 10_000,
                totalByteSize: 4_096,
                filenames: ["dune.m4b"]
            ),
            sessionCount: 1
        )
        XCTAssertTrue(BookIdentityMath.fuzzyMatch(incoming: incoming, candidate: stored))
    }

    func testFinishedSessionIsReturnedOnReuse() {
        let fingerprint = BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
        let finishedAt = Date(timeIntervalSince1970: 5_000)
        var stored = candidate(bookID: UUID(), fingerprint: fingerprint, sessionCount: 1)
        stored.finishedAt = finishedAt
        let resolved = BookIdentityMath.resolve(
            fingerprint: fingerprint,
            liveBookIDs: [],
            identities: [stored],
            orphans: [],
            stagingID: UUID()
        )
        XCTAssertEqual(resolved.finishedAt, finishedAt)
    }

    private func candidate(
        bookID: UUID,
        fingerprint: BookFingerprint,
        sessionCount: Int,
        lastSeenAt: Date = Date(timeIntervalSince1970: 1)
    ) -> BookIdentityCandidate {
        BookIdentityCandidate(
            bookID: bookID,
            identityKey: fingerprint.identityKey,
            title: fingerprint.title,
            author: fingerprint.author,
            duration: fingerprint.duration,
            totalByteSize: fingerprint.totalByteSize,
            sourceSignature: fingerprint.sourceSignature,
            probeHash: fingerprint.probeHash,
            lastSeenAt: lastSeenAt,
            sessionCount: sessionCount,
            finishedAt: nil
        )
    }
}

final class BookIdentityStoreTests: XCTestCase {
    func testReimportAfterDeleteReusesBookIDAndSessionsStayLive() {
        let container = Persistence.inMemory()
        let settings = makeSettings()
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        stats.period = .all

        let fingerprint = duneFingerprint()
        let original = insertLiveBook(container: container, library: library, fingerprint: fingerprint)
        let originalID = original.id

        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: originalID, playing: true, position: 0), now: t)
        stats.ingest(snap(bookID: originalID, playing: false, position: 80, stopReason: .pause), now: t.addingTimeInterval(80))
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)
        XCTAssertEqual(stats.allTimeSessionCount, 1)

        guard let live = library.book(id: originalID) else {
            XCTFail("Book should exist before delete")
            return
        }
        library.delete(live)
        stats.refresh()
        XCTAssertNil(library.book(id: originalID))
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertFalse(stats.recentSessions.first?.bookExists ?? true)
        XCTAssertEqual(identityCount(in: container), 1)

        let staging = UUID()
        let resolution = library.resolveIdentity(fingerprint, stagingID: staging)
        XCTAssertTrue(resolution.reused)
        XCTAssertEqual(resolution.bookID, originalID)

        insertLiveBook(container: container, library: library, fingerprint: fingerprint, id: resolution.bookID)
        stats.refresh()

        XCTAssertEqual(library.book(id: originalID)?.id, originalID)
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)
        XCTAssertEqual(stats.summary.perBook.count, 1)
        XCTAssertTrue(stats.recentSessions.first?.bookExists ?? false)
        XCTAssertEqual(stats.recentSessions.first?.bookID, originalID)
    }

    func testReimportWhileOriginalRemainsCreatesNewID() {
        let container = Persistence.inMemory()
        let library = LibraryStore(container: container)
        let fingerprint = duneFingerprint()
        let original = insertLiveBook(container: container, library: library, fingerprint: fingerprint)
        let staging = UUID()
        let resolution = library.resolveIdentity(fingerprint, stagingID: staging)
        XCTAssertFalse(resolution.reused)
        XCTAssertEqual(resolution.bookID, staging)
        XCTAssertNotEqual(resolution.bookID, original.id)
    }

    func testDeletingBookKeepsSessionsWhenIdentityExists() {
        let container = Persistence.inMemory()
        let settings = makeSettings()
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        stats.period = .all

        let fingerprint = duneFingerprint()
        let book = insertLiveBook(container: container, library: library, fingerprint: fingerprint)
        let bookID = book.id
        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: bookID, playing: true, position: 0), now: t)
        stats.ingest(snap(bookID: bookID, playing: false, position: 80, stopReason: .pause), now: t.addingTimeInterval(80))

        guard let live = library.book(id: bookID) else {
            XCTFail("Book should exist before delete")
            return
        }
        library.delete(live)
        stats.refresh()

        XCTAssertNil(library.book(id: bookID))
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)
        XCTAssertFalse(stats.recentSessions.first?.bookExists ?? true)
        XCTAssertEqual(identityCount(in: container), 1)
        XCTAssertEqual(identities(in: container).first?.bookID, bookID)
    }

    func testNewSessionsCopyIdentityKeyAndRefreshBackfills() {
        let container = Persistence.inMemory()
        let settings = makeSettings()
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        let fingerprint = duneFingerprint()
        let book = insertLiveBook(container: container, library: library, fingerprint: fingerprint)

        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: book.id, playing: true, position: 0), now: t)
        stats.ingest(snap(bookID: book.id, playing: false, position: 40, stopReason: .pause), now: t.addingTimeInterval(40))

        let sessionContext = ModelContext(container)
        let sessions = (try? sessionContext.fetch(FetchDescriptor<ListeningSession>())) ?? []
        XCTAssertEqual(sessions.first?.identityKey, fingerprint.identityKey)

        sessions.first?.identityKey = nil
        try? sessionContext.save()
        stats.refresh()
        let refreshed = (try? ModelContext(container).fetch(FetchDescriptor<ListeningSession>())) ?? []
        XCTAssertEqual(refreshed.first?.identityKey, fingerprint.identityKey)
    }

    func testFinishedAtRestoredFromIdentityOnReuse() {
        let container = Persistence.inMemory()
        let library = LibraryStore(container: container)
        let fingerprint = duneFingerprint()
        let finishedAt = Date(timeIntervalSince1970: 42)
        let original = insertLiveBook(container: container, library: library, fingerprint: fingerprint)
        original.isFinished = true
        original.finishedAt = finishedAt
        library.save()
        library.delete(original)

        let resolution = library.resolveIdentity(fingerprint, stagingID: UUID())
        XCTAssertTrue(resolution.reused)
        XCTAssertEqual(resolution.finishedAt, finishedAt)
    }

    func testImportThenDeleteThenImportSameWAVReusesIdentity() async throws {
        let container = Persistence.inMemory()
        let settings = makeSettings()
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        stats.period = .all

        let url = try makeSilentWAV(named: "Dune.wav", sampleCount: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }

        await library.importFiles([url])
        XCTAssertNil(library.importError, library.importError ?? "")
        XCTAssertEqual(library.books.count, 1)
        let originalID = try XCTUnwrap(library.books.first?.id)
        XCTAssertNotNil(library.books.first?.identityKey)
        XCTAssertEqual(library.books.first?.position, 0)

        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: originalID, playing: true, position: 0, title: "Dune"), now: t)
        stats.ingest(
            snap(bookID: originalID, playing: false, position: 80, title: "Dune", stopReason: .pause),
            now: t.addingTimeInterval(80)
        )
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)

        guard let live = library.book(id: originalID) else {
            XCTFail("Imported book missing")
            return
        }
        library.delete(live)
        stats.refresh()
        XCTAssertFalse(stats.recentSessions.first?.bookExists ?? true)

        await library.importFiles([url])
        XCTAssertNil(library.importError, library.importError ?? "")
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.books.first?.id, originalID)
        XCTAssertEqual(library.books.first?.position, 0)
        stats.refresh()
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertEqual(stats.summary.wallDuration, 80, accuracy: 0.01)
        XCTAssertTrue(stats.recentSessions.first?.bookExists ?? false)
        XCTAssertEqual(stats.recentSessions.first?.bookID, originalID)
        if let leftover = library.books.first {
            library.delete(leftover)
        }
    }

    func testImportWhileOriginalRemainsDoesNotStealSessions() async throws {
        let container = Persistence.inMemory()
        let settings = makeSettings()
        let library = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: settings)
        stats.period = .all

        let url = try makeSilentWAV(named: "Dune.wav", sampleCount: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }

        await library.importFiles([url])
        let originalID = try XCTUnwrap(library.books.first?.id)
        let t = Date(timeIntervalSince1970: 1_000_000)
        stats.ingest(snap(bookID: originalID, playing: true, position: 0, title: "Dune"), now: t)
        stats.ingest(
            snap(bookID: originalID, playing: false, position: 80, title: "Dune", stopReason: .pause),
            now: t.addingTimeInterval(80)
        )

        await library.importFiles([url])
        XCTAssertEqual(library.books.count, 2)
        let ids = Set(library.books.map(\.id))
        XCTAssertTrue(ids.contains(originalID))
        XCTAssertEqual(ids.count, 2)
        stats.refresh()
        XCTAssertEqual(stats.allTimeSessionCount, 1)
        XCTAssertEqual(stats.recentSessions.first?.bookID, originalID)
        XCTAssertTrue(stats.recentSessions.first?.bookExists ?? false)

        for book in library.books {
            library.delete(book)
        }
    }

    func testCombinedImportReusesAndSingleChapterDoesNot() async throws {
        let container = Persistence.inMemory()
        let library = LibraryStore(container: container)
        let chapter1 = try makeSilentWAV(named: "ch1.wav", sampleCount: 8_000)
        let chapter2 = try makeSilentWAV(named: "ch2.wav", sampleCount: 16_000)
        defer {
            try? FileManager.default.removeItem(at: chapter1)
            try? FileManager.default.removeItem(at: chapter2)
        }

        await library.importFiles([chapter1, chapter2])
        XCTAssertNotNil(library.pendingCombine)
        await library.resolvePendingCombine(true)
        XCTAssertEqual(library.books.count, 1)
        let combinedID = try XCTUnwrap(library.books.first?.id)
        let combinedKey = library.books.first?.identityKey

        guard let combined = library.book(id: combinedID) else {
            XCTFail("Combined book missing")
            return
        }
        library.delete(combined)

        await library.importFiles([chapter1, chapter2])
        XCTAssertNotNil(library.pendingCombine)
        await library.resolvePendingCombine(true)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.books.first?.id, combinedID)
        XCTAssertEqual(library.books.first?.identityKey, combinedKey)

        guard let liveCombined = library.book(id: combinedID) else {
            XCTFail("Reimported combined book missing")
            return
        }
        library.delete(liveCombined)

        await library.importFiles([chapter1])
        XCTAssertNil(library.pendingCombine)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertNotEqual(library.books.first?.id, combinedID)

        if let leftover = library.books.first {
            library.delete(leftover)
        }
    }

    @discardableResult
    private func insertLiveBook(
        container: ModelContainer,
        library: LibraryStore,
        fingerprint: BookFingerprint,
        id: UUID? = nil
    ) -> Book {
        let context = ModelContext(container)
        let book = Book(
            id: id ?? UUID(),
            title: fingerprint.title,
            author: fingerprint.author.isEmpty ? "Unknown Author" : fingerprint.author,
            sourceFilename: fingerprint.filenames.first ?? "dune.m4b",
            duration: fingerprint.duration
        )
        book.identityKey = fingerprint.identityKey
        let file = BookFile(relativePath: fingerprint.filenames.first ?? "dune.m4b", sortIndex: 0, duration: fingerprint.duration)
        file.book = book
        book.files = [file]
        context.insert(book)
        let existingIdentity = ((try? context.fetch(FetchDescriptor<BookIdentity>())) ?? [])
            .contains { $0.bookID == book.id }
        if !existingIdentity {
            context.insert(
                BookIdentity(
                    identityKey: fingerprint.identityKey,
                    bookID: book.id,
                    title: fingerprint.title,
                    author: fingerprint.author,
                    duration: fingerprint.duration,
                    totalByteSize: fingerprint.totalByteSize,
                    sourceSignature: fingerprint.sourceSignature,
                    probeHash: fingerprint.probeHash
                )
            )
        }
        try? context.save()
        library.refresh()
        return library.book(id: book.id) ?? book
    }

    private func duneFingerprint() -> BookFingerprint {
        BookIdentityMath.fingerprint(
            title: "Dune",
            author: "Frank Herbert",
            duration: 10_000,
            totalByteSize: 4_096,
            filenames: ["dune.m4b"]
        )
    }

    private func identities(in container: ModelContainer) -> [BookIdentity] {
        (try? ModelContext(container).fetch(FetchDescriptor<BookIdentity>())) ?? []
    }

    private func identityCount(in container: ModelContainer) -> Int {
        identities(in: container).count
    }

    private func makeSettings() -> SettingsStore {
        let suite = "chapterline.identity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.trackListeningStats = true
        return settings
    }

    private func snap(
        bookID: UUID,
        playing: Bool,
        position: TimeInterval,
        title: String = "Dune",
        stopReason: SessionEndReason? = nil
    ) -> PlayerSnapshot {
        var snapshot = PlayerSnapshot.empty
        snapshot.bookID = bookID
        snapshot.title = title
        snapshot.author = "Frank Herbert"
        snapshot.chapterTitle = "Chapter 1"
        snapshot.position = position
        snapshot.duration = 10_000
        snapshot.rate = 1
        snapshot.isPlaying = playing
        snapshot.stopReason = stopReason
        return snapshot
    }

    private func makeSilentWAV(named: String, sampleCount: Int, sampleRate: Int32 = 8_000) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(named)")
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        func ascii(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func little<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        ascii("RIFF")
        little(UInt32(36) + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        little(UInt32(16))
        little(UInt16(1))
        little(UInt16(1))
        little(UInt32(bitPattern: sampleRate))
        little(UInt32(bitPattern: sampleRate) * 2)
        little(UInt16(2))
        little(UInt16(16))
        ascii("data")
        little(dataSize)
        data.append(Data(count: Int(dataSize)))
        try data.write(to: url)
        return url
    }
}
