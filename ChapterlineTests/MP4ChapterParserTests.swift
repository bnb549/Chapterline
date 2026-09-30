import XCTest
@testable import Chapterline

final class MP4ChapterParserTests: XCTestCase {
    func testVersion0OneByteCount() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            chapters: [(0, "Intro"), (60, "Middle"), (120, "End")]
        )
        XCTAssertEqual(data[4], 3)
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.map(\.title), ["Intro", "Middle", "End"])
        XCTAssertEqual(markers.map(\.start), [0, 60, 120])
        XCTAssertEqual(markers.map(\.duration), [60, 60, 0])
        XCTAssertTrue(markers.allSatisfy { $0.source == .embedded })
    }

    func testVersion1FourByteCount() {
        let chapters = (0..<24).map { (seconds: Double($0) * 60, title: "Part \($0 + 1)") }
        let data = NeroFixture.payload(version: 1, countWidth: 4, reservedByte: false, chapters: chapters)
        XCTAssertEqual(data[0], 1)
        XCTAssertEqual(data[4], 0, "A 24-chapter count starts with 0x00 and used to be read as zero")
        XCTAssertEqual(Array(data[4..<8]), [0, 0, 0, 24])
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.count, 24)
        XCTAssertEqual(markers[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(markers[1].start, 60, accuracy: 0.001)
        XCTAssertEqual(markers[1].title, "Part 2")
        XCTAssertEqual(markers[23].title, "Part 24")
        XCTAssertEqual(markers[23].start, 23 * 60, accuracy: 0.001)
        XCTAssertEqual(markers[23].duration, 0, accuracy: 0.001)
        XCTAssertFalse(markers.contains { $0.start > 10_000 })
    }

    func testReservedByteBeforeFourByteCount() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 4,
            reservedByte: true,
            chapters: [(0, "One"), (30, "Two"), (90, "Three")]
        )
        XCTAssertEqual(data[4], 0)
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(markers.map(\.start), [0, 30, 90])
    }

    func testReservedByteBeforeOneByteCount() {
        let data = NeroFixture.payload(
            version: 1,
            countWidth: 1,
            reservedByte: true,
            chapters: [(0, "Alpha"), (15, "Beta")]
        )
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(markers[1].start, 15, accuracy: 0.001)
    }

    func testVersion1CountZeroIsEmpty() {
        let data = Data([1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(MP4ChapterParser.parseNero(data).isEmpty)
    }

    func testOverrunTitleKeepsEarlierChapters() {
        var data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            chapters: [(0, "Keep")]
        )
        data[4] = 2
        NeroFixture.append(NeroFixture.ticks(seconds: 60), to: &data)
        data.append(80)
        data.append(contentsOf: [1, 2, 3])
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].title, "Keep")
        XCTAssertEqual(markers[0].start, 0, accuracy: 0.001)
    }

    func testNonMonotonicStartIsDropped() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            chapters: [(0, "A"), (120, "B"), (60, "C"), (180, "D")]
        )
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.map(\.title), ["A", "B", "D"])
        XCTAssertEqual(markers.map(\.start), [0, 120, 180])
        XCTAssertEqual(markers.map(\.duration), [120, 60, 0])
    }

    func testTicksAreHundredNanosecondUnits() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            raw: [(ticks: 600_000_000, title: Data("Hourmark".utf8))]
        )
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].start, 60, accuracy: 0.001)
        XCTAssertEqual(markers[0].title, "Hourmark")
    }

    func testInsaneTimestampIsRejected() {
        let insane = UInt64(1_000_000_000_000) * 10_000_000
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            raw: [
                (ticks: 0, title: Data("Real".utf8)),
                (ticks: insane, title: Data("Way Out".utf8))
            ]
        )
        let markers = MP4ChapterParser.parseNero(data)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].title, "Real")
        XCTAssertLessThan(markers[0].start, 1_000_000)
        XCTAssertFalse(markers.contains { $0.start >= 1_000_000_000_000 })
    }

    func testStartBeyondFileDurationIsRejected() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            chapters: [(0, "Inside"), (5_000, "Outside")]
        )
        let markers = MP4ChapterParser.parseNero(data, fileDuration: 120)
        XCTAssertEqual(markers.map(\.title), ["Inside"])
    }

    func testLatin1Title() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            raw: [(ticks: 0, title: Data([0xE9]))]
        )
        XCTAssertEqual(MP4ChapterParser.parseNero(data).first?.title, "é")
    }

    func testChplAfterMdatIsFound() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "After"), (45, "Media")])
        let file = NeroFixture.box("mdat", Data(repeating: 0x11, count: 64))
            + NeroFixture.box("free", Data(repeating: 0, count: 8))
            + NeroFixture.box("moov", NeroFixture.box("udta", chpl))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["After", "Media"])
        XCTAssertEqual(markers[1].start, 45, accuracy: 0.001)
    }

    func testChplUnderIlstIsFound() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Listed"), (10, "Next")])
        let file = NeroFixture.box("moov", NeroFixture.box("ilst", chpl))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Listed", "Next"])
    }

    func testChplUnderUuidUserTypeIsFound() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Wrapped"), (20, "Inside")])
        var uuidPayload = Data(repeating: 0xAB, count: 16)
        uuidPayload.append(chpl)
        let file = NeroFixture.box("moov", NeroFixture.box("uuid", uuidPayload))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Wrapped", "Inside"])
    }

    func testChplUnderUuidDirectChildIsFound() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Direct")])
        let file = NeroFixture.box("moov", NeroFixture.box("uuid", chpl))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Direct"])
    }

    func testChplUnderMetaIlstIsFound() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Meta"), (5, "Child")])
        var meta = Data([0, 0, 0, 0])
        meta.append(NeroFixture.box("ilst", chpl))
        let file = NeroFixture.box("moov", NeroFixture.box("udta", NeroFixture.box("meta", meta)))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Meta", "Child"])
    }

    func testSixtyFourBitMoovStillFindsChpl() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Wide"), (8, "Box")])
        let udta = NeroFixture.box("udta", chpl)
        let file = NeroFixture.box("mdat", Data(repeating: 1, count: 24)) + NeroFixture.box64("moov", udta)
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Wide", "Box"])
    }

    func testSizeZeroMoovExtendsToEnd() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Tail")])
        let moov = NeroFixture.boxToEnd("moov", NeroFixture.box("udta", chpl))
        let file = NeroFixture.box("mdat", Data(repeating: 2, count: 12)) + moov
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Tail"])
    }

    func testDuplicateChplEntriesCollapse() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Same"), (12, "Again")])
        let file = NeroFixture.box("moov", NeroFixture.box("udta", chpl + chpl))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Same", "Again"])
    }

    func testConflictingChplPrefersLongestList() throws {
        let short = NeroFixture.chapterBox(chapters: [(0, "Short"), (10, "Only Short")])
        let long = NeroFixture.chapterBox(chapters: [(0, "Long"), (30, "Two"), (60, "Three"), (90, "Four")])
        let file = NeroFixture.box("moov", NeroFixture.box("udta", short + long))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Long", "Two", "Three", "Four"])
        XCTAssertFalse(markers.contains { abs($0.start - 10) < 0.05 })
    }

    func testMillisecondTicksRetryWhenHundredNanosecondsCluster() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            raw: [
                (ticks: 0, title: Data("One".utf8)),
                (ticks: 60_000, title: Data("Two".utf8)),
                (ticks: 120_000, title: Data("Three".utf8))
            ]
        )
        let markers = MP4ChapterParser.parseNero(data, fileDuration: 180)
        XCTAssertEqual(markers.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(markers.map(\.start), [0, 60, 120])
        XCTAssertGreaterThanOrEqual(markers.count, 2)
    }

    func testHundredNanosecondScaleStaysWhenAlreadyPlausible() {
        let data = NeroFixture.payload(
            version: 0,
            countWidth: 1,
            reservedByte: false,
            chapters: [(0, "A"), (60, "B"), (120, "C")]
        )
        let markers = MP4ChapterParser.parseNero(data, fileDuration: 180, timescales: [1_000, 44_100])
        XCTAssertEqual(markers.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(markers.map(\.start), [0, 60, 120])
    }

    func testClusteredTicksAreDroppedWhenNoScaleFits() {
        let raw = (0..<40).map { (ticks: UInt64($0), title: Data("C\($0)".utf8)) }
        let data = NeroFixture.payload(version: 0, countWidth: 1, reservedByte: false, raw: raw)
        XCTAssertTrue(MP4ChapterParser.parseNero(data, fileDuration: 3_600).isEmpty)
    }

    func testMovieTimescaleRescuesChplTicks() throws {
        let chpl = NeroFixture.box(
            "chpl",
            NeroFixture.payload(
                version: 1,
                countWidth: 4,
                reservedByte: false,
                raw: [
                    (ticks: 0, title: Data("One".utf8)),
                    (ticks: 44_100 * 60, title: Data("Two".utf8)),
                    (ticks: 44_100 * 120, title: Data("Three".utf8))
                ]
            )
        )
        let mvhd = NeroFixture.box("mvhd", NeroFixture.header(timescale: 44_100, duration: 44_100 * 180))
        let mdhd = NeroFixture.box("mdhd", NeroFixture.header(timescale: 44_100, duration: 44_100 * 180))
        let hdlr = NeroFixture.box("hdlr", NeroFixture.soundHandlerPayload())
        let file = NeroFixture.box(
            "moov",
            mvhd + NeroFixture.box("trak", NeroFixture.box("mdia", mdhd + hdlr)) + NeroFixture.box("udta", chpl)
        )
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(markers[1].start, 60, accuracy: 0.01)
        XCTAssertEqual(markers[2].start, 120, accuracy: 0.01)
    }

    func testHundredNanosecondChplIgnoresMovieTimescale() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "A"), (60, "B"), (120, "C")])
        let mvhd = NeroFixture.box("mvhd", NeroFixture.header(timescale: 44_100, duration: 44_100 * 180))
        let file = NeroFixture.box("moov", mvhd + NeroFixture.box("udta", chpl))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.start), [0, 60, 120])
    }

    func testChplUnderQuickTimeMetaWithoutFullBox() throws {
        let chpl = NeroFixture.chapterBox(chapters: [(0, "Bare"), (9, "Meta")])
        let meta = NeroFixture.box("ilst", chpl)
        let file = NeroFixture.box("moov", NeroFixture.box("udta", NeroFixture.box("meta", meta)))
        let markers = try markersInFile(file)
        XCTAssertEqual(markers.map(\.title), ["Bare", "Meta"])
        XCTAssertEqual(markers[1].start, 9, accuracy: 0.001)
    }

    private func markersInFile(_ data: Data) throws -> [ChapterMarker] {
        let url = try NeroFixture.write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        return MP4ChapterParser.chapters(from: url)
    }
}

enum NeroFixture {
    static func ticks(seconds: Double) -> UInt64 {
        UInt64((seconds * 10_000_000).rounded())
    }

    static func payload(
        version: UInt8,
        countWidth: Int,
        reservedByte: Bool,
        chapters: [(seconds: Double, title: String)]
    ) -> Data {
        let raw = chapters.map { (ticks: ticks(seconds: $0.seconds), title: Data($0.title.utf8)) }
        return payload(version: version, countWidth: countWidth, reservedByte: reservedByte, raw: raw)
    }

    static func payload(
        version: UInt8,
        countWidth: Int,
        reservedByte: Bool,
        raw: [(ticks: UInt64, title: Data)]
    ) -> Data {
        var data = Data([version, 0, 0, 0])
        if reservedByte { data.append(0) }
        if countWidth == 4 {
            append(UInt32(raw.count), to: &data)
        } else {
            data.append(UInt8(raw.count))
        }
        for chapter in raw {
            append(chapter.ticks, to: &data)
            let bytes = chapter.title.prefix(255)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        return data
    }

    static func chapterBox(chapters: [(seconds: Double, title: String)]) -> Data {
        box("chpl", payload(version: 1, countWidth: 4, reservedByte: false, chapters: chapters))
    }

    static func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        append(UInt32(8 + payload.count), to: &data)
        data.append(contentsOf: type.utf8)
        data.append(payload)
        return data
    }

    static func box64(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        append(UInt32(1), to: &data)
        data.append(contentsOf: type.utf8)
        append(UInt64(16 + payload.count), to: &data)
        data.append(payload)
        return data
    }

    static func boxToEnd(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        append(UInt32(0), to: &data)
        data.append(contentsOf: type.utf8)
        data.append(payload)
        return data
    }

    static func header(timescale: UInt32, duration: UInt32) -> Data {
        var data = Data(count: 12)
        append(timescale, to: &data)
        append(duration, to: &data)
        return data
    }

    static func soundHandlerPayload() -> Data {
        var data = Data([0, 0, 0, 0, 0, 0, 0, 0])
        data.append(contentsOf: "soun".utf8)
        return data
    }

    static func write(_ data: Data, ext: String = "m4b") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var endian = value.bigEndian
        withUnsafeBytes(of: &endian) { data.append(contentsOf: $0) }
    }
}
