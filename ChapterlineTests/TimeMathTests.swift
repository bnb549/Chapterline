import XCTest
@testable import Chapterline

final class TimeMathTests: XCTestCase {
    func testRemainingRespectsRate() {
        let remaining = TimeMath.remaining(duration: 160, position: 0, rate: 1.6)
        XCTAssertEqual(remaining, 100, accuracy: 0.01)
    }

    func testRemainingClamps() {
        XCTAssertEqual(TimeMath.remaining(duration: 10, position: 12, rate: 1), 0, accuracy: 0.01)
    }

    func testProgress() {
        XCTAssertEqual(TimeMath.progress(duration: 100, position: 25), 0.25, accuracy: 0.001)
        XCTAssertEqual(TimeMath.progress(duration: 0, position: 10), 0)
    }

    func testChapterIndex() {
        let chapters = [
            ChapterMarker(title: "One", start: 0, duration: 10, source: .embedded),
            ChapterMarker(title: "Two", start: 10, duration: 10, source: .embedded),
            ChapterMarker(title: "Three", start: 20, duration: 10, source: .embedded)
        ]
        XCTAssertEqual(TimeMath.chapterIndex(at: 0, in: chapters), 0)
        XCTAssertEqual(TimeMath.chapterIndex(at: 10, in: chapters), 1)
        XCTAssertEqual(TimeMath.chapterIndex(at: 19.9, in: chapters), 1)
        XCTAssertEqual(TimeMath.chapterIndex(at: 25, in: chapters), 2)
        XCTAssertEqual(TimeMath.chapter(at: 12, in: chapters)?.title, "Two")
    }

    func testNextPreviousChapter() {
        let chapters = [
            ChapterMarker(title: "One", start: 0, duration: 10, source: .embedded),
            ChapterMarker(title: "Two", start: 10, duration: 10, source: .embedded),
            ChapterMarker(title: "Three", start: 20, duration: 10, source: .embedded)
        ]
        XCTAssertEqual(TimeMath.nextChapterStart(at: 3, in: chapters), 10)
        XCTAssertNil(TimeMath.nextChapterStart(at: 21, in: chapters))
        // More than 3s into a chapter → restart that chapter.
        XCTAssertEqual(TimeMath.previousChapterStart(at: 14, in: chapters), 10)
        // Near the start of a chapter → previous chapter.
        XCTAssertEqual(TimeMath.previousChapterStart(at: 10.5, in: chapters), 0)
    }

    func testFileLocationMapping() {
        let durations: [TimeInterval] = [100, 50, 25]
        let mid = TimeMath.fileLocation(absoluteTime: 120, fileDurations: durations)
        XCTAssertEqual(mid.index, 1)
        XCTAssertEqual(mid.localTime, 20, accuracy: 0.01)
        XCTAssertEqual(TimeMath.absoluteTime(fileIndex: 1, localTime: 20, fileDurations: durations), 120, accuracy: 0.01)

        let end = TimeMath.fileLocation(absoluteTime: 200, fileDurations: durations)
        XCTAssertEqual(end.index, 2)
        XCTAssertEqual(end.localTime, 25, accuracy: 0.01)
    }
}
