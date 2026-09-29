import Foundation

/// Walks MP4 boxes without loading media data. Handles Nero `chpl` atoms used by many M4B files.
enum MP4ChapterParser {
    nonisolated static func chapters(from url: URL) -> [ChapterMarker] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var lists: [[ChapterMarker]] = []
        scan(handle: handle, end: fileSize(handle), into: &lists)
        return merge(lists)
    }

    nonisolated static func parseNero(_ data: Data) -> [ChapterMarker] {
        parseNero(data, fileDuration: nil)
    }

    /// Nero `chpl` FullBox.
    /// Version 0: 1-byte count at offset 4. Version 1: 4-byte count at offset 4.
    /// Some writers insert a reserved `0x00` before the count. The layout that yields the
    /// most in-buffer, monotonic chapters wins.
    nonisolated static func parseNero(_ data: Data, fileDuration: TimeInterval?) -> [ChapterMarker] {
        guard data.count >= 5 else { return [] }
        let version = data[0]
        var best: NeroDecode?
        for layout in layouts(version: version, data: data) {
            guard let decoded = decode(data, layout: layout, fileDuration: fileDuration) else { continue }
            guard !decoded.markers.isEmpty else { continue }
            if let current = best {
                if decoded.isBetter(than: current) { best = decoded }
            } else {
                best = decoded
            }
        }
        return best?.markers ?? []
    }

    private nonisolated static func fileSize(_ handle: FileHandle) -> UInt64 {
        do {
            let current = try handle.offset()
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: current)
            return size
        } catch {
            return 0
        }
    }

    private nonisolated static let containers: Set<String> = ["moov", "udta", "meta", "trak", "ilst", "uuid"]

    private nonisolated static func scan(handle: FileHandle, end: UInt64, into lists: inout [[ChapterMarker]]) {
        while true {
            guard let offset = try? handle.offset(), offset + 8 <= end else { return }
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return }
            var size32: UInt32 = 0
            var typeRaw: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &size32) { header.copyBytes(to: $0, from: 0..<4) }
            _ = withUnsafeMutableBytes(of: &typeRaw) { header.copyBytes(to: $0, from: 4..<8) }
            size32 = size32.bigEndian
            typeRaw = typeRaw.bigEndian
            let type = fourCC(typeRaw)

            var boxSize = UInt64(size32)
            var headerLength: UInt64 = 8
            if size32 == 1 {
                guard let ext = try? handle.read(upToCount: 8), ext.count == 8 else { return }
                var size64: UInt64 = 0
                _ = withUnsafeMutableBytes(of: &size64) { ext.copyBytes(to: $0) }
                boxSize = size64.bigEndian
                headerLength = 16
            } else if size32 == 0 {
                boxSize = end &- offset
            }
            guard boxSize >= headerLength, offset <= UInt64.max &- boxSize else { return }
            let payloadStart = offset + headerLength
            let payloadSize = boxSize - headerLength
            let next = offset + boxSize
            guard next > offset else { return }

            if type == "chpl" {
                let toRead = min(payloadSize, 1_000_000)
                if toRead > 0, let data = try? handle.read(upToCount: Int(toRead)), !data.isEmpty {
                    let parsed = parseNero(data)
                    if !parsed.isEmpty {
                        lists.append(parsed)
                    }
                }
            } else if type == "uuid" {
                scanUUID(handle: handle, payloadStart: payloadStart, next: next, end: end, into: &lists)
            } else if containers.contains(type) {
                // `meta` is a FullBox: version + flags occupy the first 4 payload bytes.
                let childStart = type == "meta" ? payloadStart + 4 : payloadStart
                if childStart < next {
                    try? handle.seek(toOffset: childStart)
                    scan(handle: handle, end: min(next, end), into: &lists)
                }
            }

            if next >= end { return }
            try? handle.seek(toOffset: next)
        }
    }

    /// `uuid` sometimes nests boxes immediately, and sometimes after a 16-byte user type.
    private nonisolated static func scanUUID(
        handle: FileHandle,
        payloadStart: UInt64,
        next: UInt64,
        end: UInt64,
        into lists: inout [[ChapterMarker]]
    ) {
        let limit = min(next, end)
        let before = lists.count
        if looksLikeBoxHeader(handle: handle, at: payloadStart, limit: limit) {
            try? handle.seek(toOffset: payloadStart)
            scan(handle: handle, end: limit, into: &lists)
        }
        let userTypeStart = payloadStart + 16
        if lists.count == before, userTypeStart < limit, looksLikeBoxHeader(handle: handle, at: userTypeStart, limit: limit) {
            try? handle.seek(toOffset: userTypeStart)
            scan(handle: handle, end: limit, into: &lists)
        }
    }

    private nonisolated static func looksLikeBoxHeader(handle: FileHandle, at offset: UInt64, limit: UInt64) -> Bool {
        guard offset + 8 <= limit else { return false }
        let saved = (try? handle.offset()) ?? offset
        defer { try? handle.seek(toOffset: saved) }
        guard (try? handle.seek(toOffset: offset)) != nil else { return false }
        guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return false }
        let typeBytes = [header[4], header[5], header[6], header[7]]
        guard typeBytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return false }
        let size32 = readUInt32(header, 0)
        if size32 == 0 { return true }
        if size32 == 1 { return offset + 16 <= limit }
        return size32 >= 8 && offset + UInt64(size32) <= limit
    }

    private nonisolated struct NeroLayout: Sendable {
        var countOffset: Int
        var countWidth: Int
        var preference: Int
    }

    private nonisolated struct NeroDecode: Sendable {
        var markers: [ChapterMarker]
        var complete: Bool
        var rejected: Int
        var leftover: Int
        var preference: Int

        func isBetter(than other: NeroDecode) -> Bool {
            if markers.count != other.markers.count { return markers.count > other.markers.count }
            if complete != other.complete { return complete }
            if rejected != other.rejected { return rejected < other.rejected }
            if leftover != other.leftover { return leftover < other.leftover }
            return preference < other.preference
        }
    }

    private nonisolated static func layouts(version: UInt8, data: Data) -> [NeroLayout] {
        var layouts = [
            NeroLayout(countOffset: 4, countWidth: 1, preference: version == 0 ? 0 : 3),
            NeroLayout(countOffset: 4, countWidth: 4, preference: version == 1 ? 0 : 3)
        ]
        if data.count > 4, data[4] == 0 {
            layouts.append(NeroLayout(countOffset: 5, countWidth: 1, preference: 2))
            layouts.append(NeroLayout(countOffset: 5, countWidth: 4, preference: 1))
        }
        return layouts
    }

    private nonisolated static func decode(_ data: Data, layout: NeroLayout, fileDuration: TimeInterval?) -> NeroDecode? {
        let entriesOffset = layout.countOffset + layout.countWidth
        guard entriesOffset <= data.count else { return nil }
        guard let declared = readCount(data, offset: layout.countOffset, width: layout.countWidth), declared > 0 else {
            return nil
        }
        let remaining = data.count - entriesOffset
        let maxByBytes = remaining / 9
        guard maxByBytes > 0 else { return nil }
        let capped = min(declared, 10_000, maxByBytes)
        guard capped > 0 else { return nil }
        let wasCapped = capped < declared

        var index = entriesOffset
        var parsed = 0
        var rejected = 0
        var stoppedEarly = false
        var raw: [(title: String, start: TimeInterval)] = []

        for _ in 0..<capped {
            guard index + 9 <= data.count else {
                stoppedEarly = true
                break
            }
            let ticks = readUInt64(data, index)
            index += 8
            let titleLength = Int(data[index])
            index += 1
            guard index + titleLength <= data.count else {
                stoppedEarly = true
                break
            }
            let take = min(titleLength, 1024)
            let titleData = data.subdata(in: index..<(index + take))
            index += titleLength
            parsed += 1

            let start = TimeInterval(ticks) / 10_000_000
            guard plausibleStart(start, fileDuration: fileDuration) else {
                rejected += 1
                continue
            }
            raw.append((decodeTitle(titleData), start))
        }

        var kept: [(title: String, start: TimeInterval)] = []
        for item in raw {
            if let last = kept.last, item.start < last.start { continue }
            kept.append(item)
        }
        guard !kept.isEmpty else {
            return NeroDecode(markers: [], complete: false, rejected: rejected, leftover: data.count - index, preference: layout.preference)
        }

        var markers: [ChapterMarker] = []
        markers.reserveCapacity(kept.count)
        for (offset, item) in kept.enumerated() {
            let duration = offset + 1 < kept.count ? max(0, kept[offset + 1].start - item.start) : 0
            let title = item.title.isEmpty ? "Chapter \(offset + 1)" : item.title
            markers.append(ChapterMarker(title: title, start: item.start, duration: duration, source: .embedded))
        }
        let complete = !stoppedEarly && !wasCapped && parsed == capped
        return NeroDecode(
            markers: markers,
            complete: complete,
            rejected: rejected,
            leftover: max(0, data.count - index),
            preference: layout.preference
        )
    }

    /// Drops starts that cannot be a real chapter position. `1e12` seconds is finite but not a book.
    private nonisolated static let maximumChapterStart: TimeInterval = 60 * 60 * 24 * 366 * 10

    private nonisolated static func plausibleStart(_ start: TimeInterval, fileDuration: TimeInterval?) -> Bool {
        guard start.isFinite, start >= 0, start <= maximumChapterStart else { return false }
        if let fileDuration, fileDuration > 0, start > fileDuration + 1 { return false }
        return true
    }

    private nonisolated static func decodeTitle(_ data: Data) -> String {
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func readCount(_ data: Data, offset: Int, width: Int) -> Int? {
        if width == 1 {
            guard offset < data.count else { return nil }
            return Int(data[offset])
        }
        guard offset + 4 <= data.count else { return nil }
        return Int(readUInt32(data, offset))
    }

    private nonisolated static func merge(_ lists: [[ChapterMarker]]) -> [ChapterMarker] {
        let lists = lists.filter { !$0.isEmpty }
        guard let first = lists.first else { return [] }
        if lists.count == 1 { return first }
        if conflicts(lists) {
            return lists.max { lhs, rhs in lhs.count < rhs.count } ?? first
        }
        let sorted = lists.flatMap { $0 }.sorted { $0.start < $1.start }
        var kept: [ChapterMarker] = []
        for marker in sorted {
            if let last = kept.last, marker.start <= last.start + 0.05 { continue }
            kept.append(marker)
        }
        return withDurations(kept)
    }

    /// Two full tables that disagree are not concatenated; the longer one is the chapter list.
    private nonisolated static func conflicts(_ lists: [[ChapterMarker]]) -> Bool {
        let anchored = lists.filter { ($0.first?.start ?? .infinity) <= 1 }
        guard anchored.count >= 2 else { return false }
        for index in 0..<anchored.count {
            for other in (index + 1)..<anchored.count {
                let left = anchored[index]
                let right = anchored[other]
                if !isApproximateSubset(left, of: right), !isApproximateSubset(right, of: left) {
                    return true
                }
            }
        }
        return false
    }

    private nonisolated static func isApproximateSubset(_ subset: [ChapterMarker], of universe: [ChapterMarker]) -> Bool {
        subset.allSatisfy { marker in
            universe.contains { abs($0.start - marker.start) <= 0.05 }
        }
    }

    private nonisolated static func withDurations(_ markers: [ChapterMarker]) -> [ChapterMarker] {
        var copy = markers
        for index in copy.indices {
            if index + 1 < copy.count {
                copy[index].duration = max(0, copy[index + 1].start - copy[index].start)
            } else {
                copy[index].duration = 0
            }
        }
        return copy
    }

    private nonisolated static func readUInt32(_ data: Data, _ index: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: index..<(index + 4)) }
        return value.bigEndian
    }

    private nonisolated static func readUInt64(_ data: Data, _ index: Int) -> UInt64 {
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: index..<(index + 8)) }
        return value.bigEndian
    }

    private nonisolated static func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
