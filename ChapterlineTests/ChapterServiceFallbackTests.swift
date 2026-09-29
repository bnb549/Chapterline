import XCTest
@testable import Chapterline

final class ChapterServiceFallbackTests: XCTestCase {
    private let duration: TimeInterval = 3_600

    func testDummyAVSpanLosesToRicherNero() {
        let av = [marker("Menu", start: 0, duration: duration)]
        let nero = (0..<5).map { marker("N\($0 + 1)", start: TimeInterval($0) * 60, duration: 60) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .nero)
        XCTAssertEqual(choice.markers.count, 5)
        XCTAssertEqual(choice.markers.map(\.title), ["N1", "N2", "N3", "N4", "N5"])
    }

    func testDummyTimedSpanLosesToRicherNero() {
        let timed = [marker("Chapter 1", start: 0, duration: 0)]
        let nero = (0..<4).map { marker("C\($0)", start: TimeInterval($0) * 30, duration: 30) }
        let choice = ChapterService.pickBestChapterList(av: [], timed: timed, nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .nero)
        XCTAssertEqual(choice.markers.count, 4)
    }

    func testRealSingleChapterStaysSyntheticWhenNeroEmpty() {
        let av = [marker("The Book", start: 0, duration: duration)]
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], nero: [], duration: duration)
        XCTAssertEqual(choice.path, .synthetic)
        XCTAssertTrue(choice.markers.isEmpty)
    }

    func testPartialSingleChapterIsKept() {
        let av = [marker("Only", start: 10, duration: 20)]
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], nero: [], duration: duration)
        XCTAssertEqual(choice.path, .av)
        XCTAssertEqual(choice.markers.map(\.title), ["Only"])
    }

    func testMultiChapterAVBeatsShorterNero() {
        let av = (0..<10).map { marker("A\($0)", start: TimeInterval($0) * 10, duration: 10) }
        let nero = (0..<5).map { marker("N\($0)", start: TimeInterval($0) * 20, duration: 20) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .av)
        XCTAssertEqual(choice.markers.count, 10)
    }

    func testEqualCountPrefersAVThenNero() {
        let av = [marker("A1", start: 0, duration: 50), marker("A2", start: 50, duration: 50)]
        let nero = [marker("N1", start: 0, duration: 40), marker("N2", start: 40, duration: 40)]
        let timed = [marker("T1", start: 0, duration: 30), marker("T2", start: 30, duration: 30)]
        let avOverNero = ChapterService.pickBestChapterList(av: av, timed: [], nero: nero, duration: duration)
        XCTAssertEqual(avOverNero.path, .av)
        let neroOverTimed = ChapterService.pickBestChapterList(av: [], timed: timed, nero: nero, duration: duration)
        XCTAssertEqual(neroOverTimed.path, .nero)
    }

    func testChapterLogLineFormat() {
        let line = ChapterService.chapterLogLine(filename: "Book.m4b", av: 1, timed: 0, nero: 12, chosen: 12, path: .nero)
        XCTAssertEqual(line, "chapters url=Book.m4b av=1 timed=0 nero=12 chosen=12 path=nero")
    }

    func testParseLogsNeroChoice() async throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "One"), (60, "Two"), (120, "Three")])
        let file = NeroFixture.box("mdat", Data(repeating: 0, count: 16))
            + NeroFixture.box("moov", NeroFixture.box("udta", chpl))
        let url = try NeroFixture.write(file, ext: "m4b")
        defer { try? FileManager.default.removeItem(at: url) }

        var logged: String?
        ChapterService.chapterLogSink = { logged = $0 }
        defer { ChapterService.chapterLogSink = nil }

        let markers = await ChapterService.parseChapters(files: [url], bookTitle: "Binder Book")
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers.map(\.title), ["One", "Two", "Three"])
        let line = try XCTUnwrap(logged)
        XCTAssertEqual(
            line,
            "chapters url=\(url.lastPathComponent) av=0 timed=0 nero=3 chosen=3 path=nero"
        )
        XCTAssertFalse(line.contains(url.deletingLastPathComponent().path))
    }

    func testFilesWithoutChaptersStayOneChapterEach() async throws {
        let first = try NeroFixture.write(Data([0, 1, 2, 3]), ext: "mp3")
        let second = try NeroFixture.write(Data([4, 5, 6, 7]), ext: "mp3")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let markers = await ChapterService.parseChapters(files: [first, second], bookTitle: "Combined")
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers.map(\.source), [.file, .file])
    }

    func testSingleFileWithoutChaptersUsesBookTitle() async throws {
        let url = try NeroFixture.write(Data([9, 9, 9]), ext: "mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let markers = await ChapterService.parseChapters(files: [url], bookTitle: "My Book")
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].title, "My Book")
        XCTAssertEqual(markers[0].source, .synthetic)
    }

    private func marker(_ title: String, start: TimeInterval, duration: TimeInterval) -> ChapterMarker {
        ChapterMarker(title: title, start: start, duration: duration, source: .embedded)
    }
}
