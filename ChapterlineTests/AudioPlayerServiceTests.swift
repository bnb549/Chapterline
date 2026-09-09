import XCTest
@testable import Chapterline

final class AudioPlayerServiceTests: XCTestCase {
    func testReloadingSameBookKeepsPlaybackIntent() async {
        let engine = AudioPlayerService()
        let id = UUID()
        let book = Self.makeBook(id: id, title: "Dune")

        await engine.load(book, smartRewind: true, fadeSeconds: 10, boost: 1)
        await engine.play(applyingSmartRewind: false)
        var wantsPlayback = await engine.isIntendedPlaying()
        XCTAssertTrue(wantsPlayback)

        // Tab switches re-fire BookPlayerView.onAppear, which calls load again.
        await engine.load(book, smartRewind: true, fadeSeconds: 10, boost: 1)
        wantsPlayback = await engine.isIntendedPlaying()
        XCTAssertTrue(wantsPlayback)

        let other = Self.makeBook(id: UUID(), title: "Other")
        await engine.load(other, smartRewind: true, fadeSeconds: 10, boost: 1)
        wantsPlayback = await engine.isIntendedPlaying()
        XCTAssertFalse(wantsPlayback)
    }

    func testReloadingSameBookRefreshesMetadata() async {
        let engine = AudioPlayerService()
        let id = UUID()
        await engine.load(Self.makeBook(id: id, title: "Old"), smartRewind: true, fadeSeconds: 10, boost: 1)
        await engine.load(Self.makeBook(id: id, title: "New"), smartRewind: true, fadeSeconds: 10, boost: 1)
        let snap = await engine.snapshot()
        XCTAssertEqual(snap.title, "New")
        XCTAssertEqual(snap.bookID, id)
    }

    private static func makeBook(id: UUID, title: String) -> LoadedBook {
        LoadedBook(
            id: id,
            title: title,
            author: "Author",
            narrator: nil,
            fileURLs: [URL(fileURLWithPath: "/tmp/chapterline-missing.m4b")],
            fileDurations: [100],
            chapters: [ChapterMarker(title: "Ch 1", start: 0, duration: 100, source: .embedded)],
            artworkData: nil,
            rate: 1.2,
            startPosition: 12
        )
    }
}
