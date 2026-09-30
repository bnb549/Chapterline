import XCTest
@testable import Chapterline

final class ChapterServiceFallbackTests: XCTestCase {
    private let duration: TimeInterval = 3_600

    func testDummyAVSpanLosesToRicherNero() {
        let av = [marker("Menu", start: 0, duration: duration)]
        let nero = (0..<5).map { marker("N\($0 + 1)", start: TimeInterval($0) * 60, duration: 60) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: [], nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .nero)
        XCTAssertEqual(choice.markers.count, 5)
        XCTAssertEqual(choice.markers.map(\.title), ["N1", "N2", "N3", "N4", "N5"])
    }

    func testDummyTimedSpanLosesToRicherNero() {
        let timed = [marker("Chapter 1", start: 0, duration: 0)]
        let nero = (0..<4).map { marker("C\($0)", start: TimeInterval($0) * 30, duration: 30) }
        let choice = ChapterService.pickBestChapterList(av: [], timed: timed, text: [], nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .nero)
        XCTAssertEqual(choice.markers.count, 4)
    }

    func testRealSingleChapterStaysSyntheticWhenNeroEmpty() {
        let av = [marker("The Book", start: 0, duration: duration)]
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: [], nero: [], duration: duration)
        XCTAssertEqual(choice.path, .synthetic)
        XCTAssertTrue(choice.markers.isEmpty)
    }

    func testPartialSingleChapterIsKept() {
        let av = [marker("Only", start: 10, duration: 20)]
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: [], nero: [], duration: duration)
        XCTAssertEqual(choice.path, .av)
        XCTAssertEqual(choice.markers.map(\.title), ["Only"])
    }

    func testMultiChapterAVBeatsShorterNero() {
        let av = (0..<10).map { marker("A\($0)", start: TimeInterval($0) * 10, duration: 10) }
        let nero = (0..<5).map { marker("N\($0)", start: TimeInterval($0) * 20, duration: 20) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: [], nero: nero, duration: duration)
        XCTAssertEqual(choice.path, .av)
        XCTAssertEqual(choice.markers.count, 10)
    }

    func testEqualCountPrefersAVThenNero() {
        let av = [marker("A1", start: 0, duration: 50), marker("A2", start: 50, duration: 50)]
        let nero = [marker("N1", start: 0, duration: 40), marker("N2", start: 40, duration: 40)]
        let timed = [marker("T1", start: 0, duration: 30), marker("T2", start: 30, duration: 30)]
        let avOverNero = ChapterService.pickBestChapterList(av: av, timed: [], text: [], nero: nero, duration: duration)
        XCTAssertEqual(avOverNero.path, .av)
        let neroOverTimed = ChapterService.pickBestChapterList(av: [], timed: timed, text: [], nero: nero, duration: duration)
        XCTAssertEqual(neroOverTimed.path, .nero)
    }

    func testChapterLogLineFormat() {
        let line = ChapterService.chapterLogLine(
            filename: "Book.m4b",
            av: 1,
            timed: 0,
            text: 0,
            nero: 12,
            chosen: 12,
            path: .nero,
            locales: 0,
            tracks: "soun"
        )
        XCTAssertEqual(line, "chapters url=Book.m4b av=1 timed=0 text=0 nero=12 chosen=12 path=nero locales=0 tracks=soun")
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
        XCTAssertTrue(line.hasPrefix("chapters url=\(url.lastPathComponent) av=0 timed=0 text=0 nero=3 chosen=3 path=nero "))
        XCTAssertTrue(line.contains("locales="))
        XCTAssertTrue(line.contains("tracks="))
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

    func testUndLocaleIsQueriedWhenPreferredLanguageIsEnglish() {
        let locales = ChapterService.chapterLocalesToQuery(
            available: [Locale(identifier: "und")],
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(locales.map(\.identifier), ["und"])
    }

    func testEmptyChapterLocalesFallBackToPreferredLanguages() {
        let locales = ChapterService.chapterLocalesToQuery(
            available: [],
            preferredLanguages: ["en-US", "en-US"]
        )
        XCTAssertEqual(locales.count, 1)
        XCTAssertTrue(locales[0].identifier == "en_US" || locales[0].identifier == "en-US")
    }

    func testRichestLocaleListPrefersTwoOrMoreChapters() {
        let single = [marker("Only", start: 0, duration: 10)]
        let two = [marker("X", start: 0, duration: 10), marker("Y", start: 10, duration: 10)]
        let three = [
            marker("A", start: 0, duration: 10),
            marker("B", start: 10, duration: 10),
            marker("C", start: 20, duration: 10)
        ]
        XCTAssertEqual(ChapterService.richestMarkers([single, two, three]).map(\.title), ["A", "B", "C"])
        XCTAssertEqual(ChapterService.richestMarkers([single]).map(\.title), ["Only"])
    }

    func testTextTrackSamplesBecomeMarkersAndWinThePick() {
        let samples: [(start: TimeInterval, payload: Data)] = [
            (start: 0, payload: Data("A".utf8)),
            (start: 60, payload: Data("B".utf8)),
            (start: 120, payload: Data("C".utf8))
        ]
        let text = ChapterService.markers(fromTextSamples: samples, duration: 180)
        XCTAssertEqual(text.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(text.map(\.start), [0, 60, 120])
        XCTAssertEqual(text.map(\.duration), [60, 60, 0])
        XCTAssertTrue(text.allSatisfy { $0.source == .embedded })
        let choice = ChapterService.pickBestChapterList(av: [], timed: [], text: text, nero: [], duration: 180)
        XCTAssertEqual(choice.path, .textTrack)
        XCTAssertEqual(choice.markers.count, 3)
    }

    func testDummyAVSpanLosesToRicherTextTrack() {
        let av = [marker("The Final Spark", start: 0, duration: duration)]
        let text = (0..<4).map { marker("T\($0 + 1)", start: TimeInterval($0) * 60, duration: 60) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: text, nero: [], duration: duration)
        XCTAssertEqual(choice.path, .textTrack)
        XCTAssertEqual(choice.markers.count, 4)
    }

    func testMultiChapterAVBeatsShorterTextTrack() {
        let av = (0..<10).map { marker("A\($0)", start: TimeInterval($0) * 10, duration: 10) }
        let text = (0..<3).map { marker("T\($0)", start: TimeInterval($0) * 30, duration: 30) }
        let choice = ChapterService.pickBestChapterList(av: av, timed: [], text: text, nero: [], duration: duration)
        XCTAssertEqual(choice.path, .av)
        XCTAssertEqual(choice.markers.count, 10)
    }

    func testEqualCountPrefersAVThenTextThenNeroThenTimed() {
        let av = [marker("A1", start: 0, duration: 50), marker("A2", start: 50, duration: 50)]
        let text = [marker("Q1", start: 0, duration: 45), marker("Q2", start: 45, duration: 45)]
        let nero = [marker("N1", start: 0, duration: 40), marker("N2", start: 40, duration: 40)]
        let timed = [marker("T1", start: 0, duration: 30), marker("T2", start: 30, duration: 30)]
        XCTAssertEqual(
            ChapterService.pickBestChapterList(av: av, timed: [], text: text, nero: nero, duration: duration).path,
            .av
        )
        XCTAssertEqual(
            ChapterService.pickBestChapterList(av: [], timed: [], text: text, nero: nero, duration: duration).path,
            .textTrack
        )
        XCTAssertEqual(
            ChapterService.pickBestChapterList(av: [], timed: timed, text: [], nero: nero, duration: duration).path,
            .nero
        )
    }

    func testChapterListAssociationIgnoresDecoyTextTrack() {
        let chosen = ChapterService.chapterTextTrackIDsToRead(associated: [2], candidates: [2, 5])
        XCTAssertEqual(chosen, [2])
        let fallback = ChapterService.chapterTextTrackIDsToRead(associated: [], candidates: [2, 5, 2])
        XCTAssertEqual(fallback, [2, 5])
    }

    func testUTF8TextSampleDecodes() {
        XCTAssertEqual(ChapterService.decodeChapterTextSample(Data("Alpha".utf8), index: 1), "Alpha")
    }

    func testUTF16BigEndianTextSampleDecodes() {
        var data = Data([0xFE, 0xFF])
        data.append(contentsOf: [0x00, 0x48, 0x00, 0x69])
        XCTAssertEqual(ChapterService.decodeChapterTextSample(data, index: 1), "Hi")
        XCTAssertEqual(ChapterService.decodeChapterTextSample(Data([0x00, 0xE9]), index: 2), "é")
    }

    func testUTF16LittleEndianTextSampleDecodes() {
        var data = Data([0xFF, 0xFE])
        data.append(contentsOf: [0x48, 0x00, 0x69, 0x00])
        XCTAssertEqual(ChapterService.decodeChapterTextSample(data, index: 1), "Hi")
        XCTAssertEqual(ChapterService.decodeChapterTextSample(Data([0xE9, 0x00]), index: 2), "é")
    }

    func testQuickTimeLengthPrefixedTextSampleDecodes() {
        var data = Data([0x00, 0x05])
        data.append(contentsOf: "Intro".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: "encd".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(ChapterService.decodeChapterTextSample(data, index: 1), "Intro")
    }

    func testTx3gLengthPrefixedUTF16Decodes() {
        let data = Data([0x00, 0x04, 0x00, 0x48, 0x00, 0x69])
        XCTAssertEqual(ChapterService.decodeChapterTextSample(data, index: 1), "Hi")
    }

    func testEmptyTextSampleUsesChapterNumber() {
        XCTAssertEqual(ChapterService.decodeChapterTextSample(Data(), index: 4), "Chapter 4")
        let nulled = Data([0x41, 0x00, 0x42])
        XCTAssertEqual(ChapterService.decodeChapterTextSample(nulled, index: 1), "AB")
    }

    func testTextSampleTitleIsCappedAndOutOfRangeSamplesDrop() {
        let long = String(repeating: "A", count: 2_000)
        XCTAssertEqual(ChapterService.decodeChapterTextSample(Data(long.utf8), index: 1).count, 1_024)
        let late: [(start: TimeInterval, payload: Data)] = [
            (start: 0, payload: Data("Keep".utf8)),
            (start: 5_000, payload: Data("Late".utf8))
        ]
        XCTAssertEqual(ChapterService.markers(fromTextSamples: late, duration: 30).map(\.title), ["Keep"])
        let backwards: [(start: TimeInterval, payload: Data)] = [
            (start: 0, payload: Data("Keep".utf8)),
            (start: 20, payload: Data("Next".utf8)),
            (start: 10, payload: Data("Back".utf8))
        ]
        XCTAssertEqual(ChapterService.markers(fromTextSamples: backwards, duration: 30).map(\.title), ["Keep", "Next"])
    }

    func testChapterLogLineIncludesTextTrackPath() {
        let line = ChapterService.chapterLogLine(
            filename: "Spark.m4b",
            av: 1,
            timed: 0,
            text: 55,
            nero: 0,
            chosen: 55,
            path: .textTrack,
            locales: 1,
            tracks: "soun,text"
        )
        XCTAssertEqual(
            line,
            "chapters url=Spark.m4b av=1 timed=0 text=55 nero=0 chosen=55 path=textTrack locales=1 tracks=soun,text"
        )
    }

    func testSyntheticFallbackWhenEveryChapterSourceIsEmpty() {
        let choice = ChapterService.pickBestChapterList(
            av: [marker("The Final Spark", start: 0, duration: duration)],
            timed: [],
            text: [],
            nero: [],
            duration: duration
        )
        XCTAssertEqual(choice.path, .synthetic)
        XCTAssertTrue(choice.markers.isEmpty)
    }

    private func marker(_ title: String, start: TimeInterval, duration: TimeInterval) -> ChapterMarker {
        ChapterMarker(title: title, start: start, duration: duration, source: .embedded)
    }
}
