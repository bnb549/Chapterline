import XCTest
@testable import Chapterline

final class NowPlayingChromeTests: XCTestCase {
    func testListeningRequiresPlayingAndBook() {
        var snap = PlayerSnapshot.empty
        XCTAssertFalse(NowPlayingChrome.isListening(snap))

        snap.bookID = UUID()
        XCTAssertFalse(NowPlayingChrome.isListening(snap))

        snap.isPlaying = true
        XCTAssertTrue(NowPlayingChrome.isListening(snap))

        snap.bookID = nil
        XCTAssertFalse(NowPlayingChrome.isListening(snap))
    }

    func testBarPrefersThePlayingBook() {
        let playing = UUID()
        let other = UUID()
        let content = NowPlayingChrome.barContent(
            snapshotBookID: playing,
            isPlaying: true,
            loadedBookIsFinished: false,
            continueBookID: other
        )
        XCTAssertEqual(content, NowPlayingChrome.Content(bookID: playing, isPlaying: true))
    }

    func testBarKeepsAPausedUnfinishedBook() {
        let session = UUID()
        let other = UUID()
        let content = NowPlayingChrome.barContent(
            snapshotBookID: session,
            isPlaying: false,
            loadedBookIsFinished: false,
            continueBookID: other
        )
        XCTAssertEqual(content, NowPlayingChrome.Content(bookID: session, isPlaying: false))
    }

    func testFinishedOrMissingLoadedBookFallsThroughToContinue() {
        let finished = UUID()
        let resume = UUID()
        XCTAssertEqual(
            NowPlayingChrome.barContent(
                snapshotBookID: finished,
                isPlaying: false,
                loadedBookIsFinished: true,
                continueBookID: resume
            ),
            NowPlayingChrome.Content(bookID: resume, isPlaying: false)
        )
        XCTAssertEqual(
            NowPlayingChrome.barContent(
                snapshotBookID: finished,
                isPlaying: false,
                loadedBookIsFinished: nil,
                continueBookID: resume
            ),
            NowPlayingChrome.Content(bookID: resume, isPlaying: false)
        )
    }

    func testColdStartUsesContinueBook() {
        let resume = UUID()
        let content = NowPlayingChrome.barContent(
            snapshotBookID: nil,
            isPlaying: false,
            loadedBookIsFinished: nil,
            continueBookID: resume
        )
        XCTAssertEqual(content, NowPlayingChrome.Content(bookID: resume, isPlaying: false))
    }

    func testBarHidesWhenNothingCanResume() {
        XCTAssertNil(
            NowPlayingChrome.barContent(
                snapshotBookID: nil,
                isPlaying: false,
                loadedBookIsFinished: nil,
                continueBookID: nil
            )
        )
        XCTAssertNil(
            NowPlayingChrome.barContent(
                snapshotBookID: UUID(),
                isPlaying: false,
                loadedBookIsFinished: true,
                continueBookID: nil
            )
        )
    }

    func testDetailPrefersChapterThenRemainingRules() {
        XCTAssertEqual(
            NowPlayingChrome.detailLine(
                chapterTitle: "Chapter 2",
                hideRemainingTime: true,
                isFinished: false,
                progress: 0.5,
                duration: 100,
                position: 50,
                rate: 1
            ),
            "Chapter 2"
        )
        XCTAssertEqual(
            NowPlayingChrome.detailLine(
                chapterTitle: "   ",
                hideRemainingTime: false,
                isFinished: false,
                progress: 0,
                duration: 3600,
                position: 0,
                rate: 1
            ),
            "1h 0m left"
        )
        XCTAssertEqual(
            NowPlayingChrome.detailLine(
                chapterTitle: "",
                hideRemainingTime: true,
                isFinished: false,
                progress: 0.42,
                duration: 100,
                position: 42,
                rate: 1
            ),
            "42%"
        )
        XCTAssertEqual(
            NowPlayingChrome.detailLine(
                chapterTitle: "",
                hideRemainingTime: true,
                isFinished: true,
                progress: 1,
                duration: 100,
                position: 100,
                rate: 1
            ),
            "Finished"
        )
        XCTAssertEqual(
            NowPlayingChrome.detailLine(
                chapterTitle: "",
                hideRemainingTime: false,
                isFinished: true,
                progress: 1,
                duration: 100,
                position: 100,
                rate: 1
            ),
            "Finished"
        )
    }
}
