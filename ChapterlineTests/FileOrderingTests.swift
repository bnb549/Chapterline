import XCTest
@testable import Chapterline

final class FileOrderingTests: XCTestCase {
    func testNumericFilenameOrder() {
        let names = ["ch10.mp3", "ch2.mp3", "ch1.mp3"]
        XCTAssertEqual(FileOrdering.combineSortNames(names), ["ch1.mp3", "ch2.mp3", "ch10.mp3"])
    }

    func testURLOrder() {
        let urls = [
            URL(fileURLWithPath: "/tmp/Track 10.m4b"),
            URL(fileURLWithPath: "/tmp/Track 2.m4b"),
            URL(fileURLWithPath: "/tmp/Track 1.m4b")
        ]
        let sorted = FileOrdering.combineSort(urls).map(\.lastPathComponent)
        XCTAssertEqual(sorted, ["Track 1.m4b", "Track 2.m4b", "Track 10.m4b"])
    }

    func testDisplayTitle() {
        XCTAssertEqual(FileOrdering.displayTitle(from: "The_Hobbit.m4b"), "The Hobbit")
    }
}

final class DRMGuardTests: XCTestCase {
    func testRejectsAudibleExtensions() {
        XCTAssertTrue(DRMGuard.isBlocked(extension: "aa"))
        XCTAssertTrue(DRMGuard.isBlocked(extension: "AAX"))
        XCTAssertFalse(DRMGuard.isBlocked(extension: "m4b"))
        XCTAssertFalse(DRMGuard.isBlocked(extension: "mp3"))
    }

    func testURLCheck() {
        XCTAssertTrue(DRMGuard.isBlocked(URL(fileURLWithPath: "/tmp/book.aax")))
        XCTAssertFalse(DRMGuard.isBlocked(URL(fileURLWithPath: "/tmp/book.m4b")))
    }
}

final class SkipIntervalTests: XCTestCase {
    func testStorageRoundTrip() {
        XCTAssertEqual(SkipInterval(storageValue: "s-15"), .seconds(15))
        XCTAssertEqual(SkipInterval(storageValue: "s-30"), .seconds(30))
        XCTAssertEqual(SkipInterval(storageValue: "chapter"), .chapter)
        XCTAssertEqual(SkipInterval.chapter.storageValue, "chapter")
    }

    func testChapterFlag() {
        XCTAssertTrue(SkipInterval.chapter.isChapter)
        XCTAssertFalse(SkipInterval.seconds(15).isChapter)
        XCTAssertEqual(SkipInterval.seconds(45).secondsValue, 45)
    }
}
