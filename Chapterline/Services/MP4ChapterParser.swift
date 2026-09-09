import Foundation

/// Walks MP4 boxes without loading media data. Handles Nero `chpl` atoms used by many M4B files.
enum MP4ChapterParser {
    static func chapters(from url: URL) -> [ChapterMarker] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var markers: [ChapterMarker] = []
        scan(handle: handle, end: fileSize(handle), into: &markers)
        return markers
    }

    private static func fileSize(_ handle: FileHandle) -> UInt64 {
        do {
            let current = try handle.offset()
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: current)
            return size
        } catch {
            return 0
        }
    }

    private static func scan(handle: FileHandle, end: UInt64, into markers: inout [ChapterMarker]) {
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
                boxSize = end - offset
            }
            guard boxSize >= headerLength else { return }
            let payloadStart = offset + headerLength
            let payloadSize = boxSize - headerLength
            let next = offset + boxSize

            if type == "chpl" {
                if let data = try? handle.read(upToCount: Int(min(payloadSize, 1_000_000))) {
                    markers.append(contentsOf: parseNero(data))
                }
            } else if type == "moov" || type == "udta" || type == "meta" || type == "trak" {
                if payloadStart < next {
                    try? handle.seek(toOffset: payloadStart)
                    scan(handle: handle, end: min(next, end), into: &markers)
                }
            }

            if next >= end { return }
            try? handle.seek(toOffset: next)
        }
    }

    /// Nero `chpl`: version/flags (4), count (1 or 4), then chapters of 8-byte timestamp (100 ns units) + length-prefixed title.
    private static func parseNero(_ data: Data) -> [ChapterMarker] {
        guard data.count >= 5 else { return [] }
        var index = 0
        if data.count > 8 { index = 4 }
        var count = Int(data[index])
        index += 1
        if count == 0, data.count > index + 4 {
            count = Int(readUInt32(data, index))
            index += 4
        }
        var starts: [(title: String, start: TimeInterval)] = []
        for _ in 0..<count {
            guard index + 9 <= data.count else { break }
            let ticks = readUInt64(data, index)
            index += 8
            let titleLength = Int(data[index])
            index += 1
            guard index + titleLength <= data.count else { break }
            let titleData = data.subdata(in: index..<(index + titleLength))
            index += titleLength
            let title = String(data: titleData, encoding: .utf8)
                ?? String(data: titleData, encoding: .isoLatin1)
                ?? "Chapter \(starts.count + 1)"
            let start = TimeInterval(ticks) / 10_000_000
            starts.append((title.trimmingCharacters(in: .whitespacesAndNewlines), start))
        }
        var markers: [ChapterMarker] = []
        for (i, item) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].start : item.start
            let duration = max(0, end - item.start)
            markers.append(ChapterMarker(title: item.title.isEmpty ? "Chapter \(i + 1)" : item.title, start: item.start, duration: duration, source: .embedded))
        }
        return markers
    }

    private static func readUInt32(_ data: Data, _ index: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: index..<(index + 4)) }
        return value.bigEndian
    }

    private static func readUInt64(_ data: Data, _ index: Int) -> UInt64 {
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: index..<(index + 8)) }
        return value.bigEndian
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
