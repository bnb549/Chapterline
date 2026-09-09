import XCTest
@testable import Chapterline

final class SmartRewindTests: XCTestCase {
    func testDisabled() {
        XCTAssertEqual(SmartRewind.seconds(forGap: 120, enabled: false), 0)
    }

    func testTinyGap() {
        XCTAssertEqual(SmartRewind.seconds(forGap: 0.4, enabled: true), 0)
    }

    func testShortPause() {
        XCTAssertEqual(SmartRewind.seconds(forGap: 10, enabled: true), 3, accuracy: 0.01)
    }

    func testLongPause() {
        XCTAssertEqual(SmartRewind.seconds(forGap: 20 * 60, enabled: true), 30, accuracy: 0.01)
    }

    func testLerpWindow() {
        let value = SmartRewind.seconds(forGap: 30 + (10 * 60 - 30) / 2, enabled: true)
        XCTAssertEqual(value, (3 + 20) / 2, accuracy: 0.2)
    }

    func testDoesNotCrossChapterStart() {
        let now = Date()
        let pause = now.addingTimeInterval(-120)
        let applied = SmartRewind.apply(
            position: 12,
            lastPauseAt: pause,
            now: now,
            chapterStart: 10,
            enabled: true
        )
        XCTAssertEqual(applied, 10, accuracy: 0.01)
    }
}
