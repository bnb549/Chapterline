import Foundation

/// Walks MP4 boxes without loading media data. Handles Nero `chpl` atoms used by many M4B files.
enum MP4ChapterParser {
    nonisolated static func chapters(from url: URL) -> [ChapterMarker] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var state = WalkState()
        scan(handle: handle, end: fileSize(handle), state: &state)
        var timescales: [UInt32] = []
        if let movie = state.movieTimescale, movie > 0 {
            timescales.append(movie)
        }
        if let audio = state.audioTimescale, audio > 0, audio != state.movieTimescale {
            timescales.append(audio)
        }
        let duration = (state.movieDuration ?? 0) > 0 ? state.movieDuration : nil
        var lists: [[ChapterMarker]] = []
        for payload in state.chplPayloads {
            let parsed = parseNero(payload, fileDuration: duration, timescales: timescales)
            if !parsed.isEmpty {
                lists.append(parsed)
            }
        }
        return merge(lists)
    }

    nonisolated static func parseNero(_ data: Data) -> [ChapterMarker] {
        parseNero(data, fileDuration: nil)
    }

    /// Nero `chpl` FullBox.
    /// Version 0: 1-byte count at offset 4. Version 1: 4-byte count at offset 4.
    /// Some writers insert a reserved `0x00` before the count. The layout that yields the
    /// most in-buffer, monotonic chapters wins. Timestamps are 100 ns units unless that
    /// scale yields fewer than two plausible markers, in which case other divisors are tried.
    nonisolated static func parseNero(
        _ data: Data,
        fileDuration: TimeInterval?,
        timescales: [UInt32] = []
    ) -> [ChapterMarker] {
        guard data.count >= 5 else { return [] }
        let version = data[0]
        var best: NeroDecode?
        var fallback: NeroDecode?
        for layout in layouts(version: version, data: data) {
            guard let decoded = decode(data, layout: layout, fileDuration: fileDuration) else { continue }
            if !decoded.entries.isEmpty {
                if let current = fallback {
                    if decoded.entries.count > current.entries.count { fallback = decoded }
                } else {
                    fallback = decoded
                }
            }
            guard !decoded.markers.isEmpty else { continue }
            if let current = best {
                if decoded.isBetter(than: current) { best = decoded }
            } else {
                best = decoded
            }
        }
        guard let chosen = best ?? fallback else { return [] }
        return applyTimescale(chosen, fileDuration: fileDuration, timescales: timescales)
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

    private nonisolated static let containers: Set<String> = ["moov", "udta", "trak", "ilst", "uuid", "mdia"]

    private nonisolated struct WalkState {
        var chplPayloads: [Data] = []
        var movieTimescale: UInt32?
        var movieDuration: TimeInterval?
        var audioTimescale: UInt32?
        var traks: [TrakProbe] = []
        var currentTrak: Int?
    }

    private nonisolated struct TrakProbe {
        var isAudio = false
        var mediaTimescale: UInt32?
    }

    private nonisolated static func scan(handle: FileHandle, end: UInt64, state: inout WalkState) {
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
                    state.chplPayloads.append(data)
                }
            } else if type == "uuid" {
                scanUUID(handle: handle, payloadStart: payloadStart, next: next, end: end, state: &state)
            } else if type == "mvhd" {
                if let header = readMediaHeader(handle: handle, payloadSize: payloadSize) {
                    if state.movieTimescale == nil { state.movieTimescale = header.timescale }
                    if state.movieDuration == nil, header.duration > 0 { state.movieDuration = header.duration }
                }
            } else if type == "mdhd" {
                if let header = readMediaHeader(handle: handle, payloadSize: payloadSize),
                   let index = state.currentTrak, state.traks.indices.contains(index) {
                    state.traks[index].mediaTimescale = header.timescale
                }
            } else if type == "hdlr" {
                noteHandler(handle: handle, payloadSize: payloadSize, state: &state)
            } else if type == "meta" {
                walkMeta(handle: handle, payloadStart: payloadStart, next: next, end: end, state: &state)
            } else if containers.contains(type) {
                let saved = state.currentTrak
                if type == "trak" {
                    state.traks.append(TrakProbe())
                    state.currentTrak = state.traks.count - 1
                }
                if payloadStart < next {
                    try? handle.seek(toOffset: payloadStart)
                    scan(handle: handle, end: min(next, end), state: &state)
                }
                if type == "trak", let index = state.currentTrak, state.traks.indices.contains(index) {
                    let probe = state.traks[index]
                    if state.audioTimescale == nil, probe.isAudio, let scale = probe.mediaTimescale, scale > 0 {
                        state.audioTimescale = scale
                    }
                }
                state.currentTrak = saved
            }

            if next >= end { return }
            try? handle.seek(toOffset: next)
        }
    }

    /// QuickTime `meta` is not a FullBox. ISO `meta` is. Keep the walk that finds `chpl`.
    private nonisolated static func walkMeta(
        handle: FileHandle,
        payloadStart: UInt64,
        next: UInt64,
        end: UInt64,
        state: inout WalkState
    ) {
        let limit = min(next, end)
        var quicktime = WalkState()
        var fullbox = WalkState()
        if payloadStart < limit {
            try? handle.seek(toOffset: payloadStart)
            scan(handle: handle, end: limit, state: &quicktime)
        }
        let fullStart = payloadStart + 4
        if fullStart < limit {
            try? handle.seek(toOffset: fullStart)
            scan(handle: handle, end: limit, state: &fullbox)
        }
        let chosen = chooseMeta(quicktime: quicktime, fullbox: fullbox)
        state.chplPayloads.append(contentsOf: chosen.chplPayloads)
        if state.movieTimescale == nil {
            state.movieTimescale = chosen.movieTimescale ?? quicktime.movieTimescale ?? fullbox.movieTimescale
        }
        if state.movieDuration == nil {
            state.movieDuration = chosen.movieDuration ?? quicktime.movieDuration ?? fullbox.movieDuration
        }
        if state.audioTimescale == nil {
            state.audioTimescale = chosen.audioTimescale ?? quicktime.audioTimescale ?? fullbox.audioTimescale
        }
    }

    private nonisolated static func chooseMeta(quicktime: WalkState, fullbox: WalkState) -> WalkState {
        let quicktimeCount = quicktime.chplPayloads.count
        let fullboxCount = fullbox.chplPayloads.count
        if quicktimeCount > fullboxCount { return quicktime }
        if fullboxCount > quicktimeCount { return fullbox }
        let quicktimeBytes = quicktime.chplPayloads.reduce(0) { $0 + $1.count }
        let fullboxBytes = fullbox.chplPayloads.reduce(0) { $0 + $1.count }
        if quicktimeBytes > fullboxBytes { return quicktime }
        return fullbox
    }

    /// `uuid` sometimes nests boxes immediately, and sometimes after a 16-byte user type.
    private nonisolated static func scanUUID(
        handle: FileHandle,
        payloadStart: UInt64,
        next: UInt64,
        end: UInt64,
        state: inout WalkState
    ) {
        let limit = min(next, end)
        let before = state.chplPayloads.count
        if looksLikeBoxHeader(handle: handle, at: payloadStart, limit: limit) {
            try? handle.seek(toOffset: payloadStart)
            scan(handle: handle, end: limit, state: &state)
        }
        let userTypeStart = payloadStart + 16
        if state.chplPayloads.count == before, userTypeStart < limit, looksLikeBoxHeader(handle: handle, at: userTypeStart, limit: limit) {
            try? handle.seek(toOffset: userTypeStart)
            scan(handle: handle, end: limit, state: &state)
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

    private nonisolated static func readMediaHeader(handle: FileHandle, payloadSize: UInt64) -> (timescale: UInt32, duration: TimeInterval)? {
        let toRead = min(payloadSize, 48)
        guard toRead >= 20, let data = try? handle.read(upToCount: Int(toRead)) else { return nil }
        return readHeaderTimescale(data)
    }

    private nonisolated static func readHeaderTimescale(_ data: Data) -> (timescale: UInt32, duration: TimeInterval)? {
        guard !data.isEmpty else { return nil }
        let version = data[0]
        let timescale: UInt32
        let rawDuration: UInt64
        if version == 0 {
            guard data.count >= 20 else { return nil }
            timescale = readUInt32(data, 12)
            rawDuration = UInt64(readUInt32(data, 16))
        } else if version == 1 {
            guard data.count >= 32 else { return nil }
            timescale = readUInt32(data, 20)
            rawDuration = readUInt64(data, 24)
        } else {
            return nil
        }
        guard timescale > 0 else { return nil }
        return (timescale, TimeInterval(rawDuration) / TimeInterval(timescale))
    }

    private nonisolated static func noteHandler(handle: FileHandle, payloadSize: UInt64, state: inout WalkState) {
        guard let index = state.currentTrak, state.traks.indices.contains(index) else { return }
        let toRead = min(payloadSize, 64)
        guard toRead >= 12, let data = try? handle.read(upToCount: Int(toRead)), data.count >= 12 else { return }
        if fourCC(readUInt32(data, 8)) == "soun" {
            state.traks[index].isAudio = true
        }
    }

    private nonisolated struct RawChapter: Sendable {
        var ticks: UInt64
        var title: String
    }

    private nonisolated struct NeroLayout: Sendable {
        var countOffset: Int
        var countWidth: Int
        var preference: Int
    }

    private nonisolated struct NeroDecode: Sendable {
        var markers: [ChapterMarker]
        var entries: [RawChapter]
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
        var entries: [RawChapter] = []
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

            let title = decodeTitle(titleData)
            entries.append(RawChapter(ticks: ticks, title: title))
            let start = TimeInterval(ticks) / 10_000_000
            guard plausibleStart(start, fileDuration: fileDuration) else {
                rejected += 1
                continue
            }
            raw.append((title, start))
        }

        var kept: [(title: String, start: TimeInterval)] = []
        for item in raw {
            if let last = kept.last, item.start < last.start { continue }
            kept.append(item)
        }
        let markers = chapterMarkers(from: kept)
        let complete = !stoppedEarly && !wasCapped && parsed == capped
        return NeroDecode(
            markers: markers,
            entries: entries,
            complete: complete,
            rejected: rejected,
            leftover: max(0, data.count - index),
            preference: layout.preference
        )
    }

    /// 100 ns stays when it already yields two or more markers that span the file.
    /// Otherwise the same ticks are scored at µs, ms, seconds, and any movie/audio timescale.
    private nonisolated static func applyTimescale(
        _ decoded: NeroDecode,
        fileDuration: TimeInterval?,
        timescales: [UInt32]
    ) -> [ChapterMarker] {
        if spreadQualifies(decoded.markers, fileDuration: fileDuration) {
            return decoded.markers
        }
        var divisors: [UInt64] = [10_000_000, 1_000_000, 1_000, 1]
        for scale in timescales where scale > 0 {
            let value = UInt64(scale)
            if !divisors.contains(value) {
                divisors.append(value)
            }
        }
        var bestScore = 0
        var best: [ChapterMarker]?
        for divisor in divisors {
            let markers = markers(from: decoded.entries, divisor: divisor, fileDuration: fileDuration)
            let score = spreadQualifies(markers, fileDuration: fileDuration) ? markers.count : 0
            if score >= 2, score > bestScore {
                bestScore = score
                best = markers
            }
        }
        if let best { return best }
        if decoded.markers.count >= 2 { return [] }
        return decoded.markers
    }

    private nonisolated static func markers(
        from entries: [RawChapter],
        divisor: UInt64,
        fileDuration: TimeInterval?
    ) -> [ChapterMarker] {
        guard divisor > 0 else { return [] }
        var kept: [(title: String, start: TimeInterval)] = []
        for entry in entries {
            let start = TimeInterval(entry.ticks) / TimeInterval(divisor)
            guard plausibleStart(start, fileDuration: fileDuration) else { continue }
            if let last = kept.last, start < last.start { continue }
            kept.append((entry.title, start))
        }
        return chapterMarkers(from: kept)
    }

    private nonisolated static func chapterMarkers(from kept: [(title: String, start: TimeInterval)]) -> [ChapterMarker] {
        guard !kept.isEmpty else { return [] }
        var markers: [ChapterMarker] = []
        markers.reserveCapacity(kept.count)
        for (offset, item) in kept.enumerated() {
            let duration = offset + 1 < kept.count ? max(0, kept[offset + 1].start - item.start) : 0
            let title = item.title.isEmpty ? "Chapter \(offset + 1)" : item.title
            markers.append(ChapterMarker(title: title, start: item.start, duration: duration, source: .embedded))
        }
        return markers
    }

    /// Count >= 2, strictly usable against `fileDuration` when it is known.
    /// Unknown duration keeps a 100 ns list of two or more; a known duration also requires spread.
    private nonisolated static func spreadQualifies(_ markers: [ChapterMarker], fileDuration: TimeInterval?) -> Bool {
        guard markers.count >= 2, let first = markers.first, let last = markers.last else { return false }
        if let fileDuration, fileDuration > 0, last.start > fileDuration + 1 { return false }
        guard let fileDuration, fileDuration > 0 else { return true }
        let minimum = min(60, 0.05 * fileDuration)
        return last.start - first.start + 0.000_001 >= minimum
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
