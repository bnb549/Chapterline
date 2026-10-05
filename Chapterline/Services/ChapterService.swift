import AVFoundation
import CoreMedia
import Foundation
import os

struct BookMetadata: Sendable {
    var title: String?
    var author: String?
    var narrator: String?
    var artwork: Data?
    var duration: TimeInterval
}

nonisolated enum ChapterPickPath: String, Equatable, Sendable {
    case av
    case textTrack
    case timed
    case nero
    case synthetic
}

nonisolated struct ChapterListChoice: Equatable, Sendable {
    var markers: [ChapterMarker]
    var path: ChapterPickPath
}

enum ChapterService {
    private static let chapterLogger = Logger(subsystem: "com.benmonroe.ChapterLine", category: "chapters")
    private nonisolated static let sampleCap = 10_000
    private nonisolated static let titleCap = 1_024
    private nonisolated static let qtTextSubtype: FourCharCode = 0x74657874
    private nonisolated static let tx3gSubtype: FourCharCode = 0x74783367
    private nonisolated static let c608Subtype: FourCharCode = 0x63363038

    /// Test hook. Production parses still go through `os.Logger`.
    static var chapterLogSink: ((String) -> Void)?

    static func inspect(url: URL) async -> BookMetadata {
        let asset = AVURLAsset(url: url)
        let duration = (try? await seconds(of: asset)) ?? 0
        var title: String?
        var author: String?
        var narrator: String?
        var artwork: Data?

        if let common = try? await asset.load(.commonMetadata) {
            title = await stringValue(in: common, identifier: .commonIdentifierTitle)
            author = await stringValue(in: common, identifier: .commonIdentifierArtist)
            if author == nil {
                author = await stringValue(in: common, identifier: .commonIdentifierCreator)
            }
            artwork = await dataValue(in: common, identifier: .commonIdentifierArtwork)
        }
        if let iTunes = try? await asset.load(.metadata) {
            if narrator == nil {
                narrator = await stringValue(in: iTunes, identifier: .iTunesMetadataPerformer)
            }
            if author == nil {
                author = await stringValue(in: iTunes, identifier: .iTunesMetadataAlbumArtist)
            }
            if author == nil {
                author = await stringValue(in: iTunes, identifier: .iTunesMetadataArtist)
            }
            if title == nil {
                title = await stringValue(in: iTunes, identifier: .iTunesMetadataSongName)
            }
            if artwork == nil {
                artwork = await dataValue(in: iTunes, identifier: .iTunesMetadataCoverArt)
            }
        }
        return BookMetadata(title: title, author: author, narrator: narrator, artwork: artwork, duration: duration)
    }

    nonisolated static func chapterLogLine(
        filename: String,
        av: Int,
        timed: Int,
        text: Int,
        nero: Int,
        chosen: Int,
        path: ChapterPickPath,
        locales: Int,
        tracks: String
    ) -> String {
        "chapters url=\(filename) av=\(av) timed=\(timed) text=\(text) nero=\(nero) chosen=\(chosen) path=\(path.rawValue) locales=\(locales) tracks=\(tracks)"
    }

    /// Rank lists with at least two markers. Tie-break: av, text track, Nero, timed.
    nonisolated static func pickBestChapterList(
        av: [ChapterMarker],
        timed: [ChapterMarker],
        text: [ChapterMarker],
        nero: [ChapterMarker],
        duration: TimeInterval
    ) -> ChapterListChoice {
        let avList = sanitize(av, duration: duration)
        let textList = sanitize(text, duration: duration)
        let timedList = sanitize(timed, duration: duration)
        let neroList = sanitize(nero, duration: duration)
        let ranked: [(markers: [ChapterMarker], path: ChapterPickPath)] = [
            (avList, .av),
            (textList, .textTrack),
            (neroList, .nero),
            (timedList, .timed)
        ]
        let rich = ranked.filter { $0.markers.count >= 2 }
        if let best = rich.max(by: { lhs, rhs in
            if lhs.markers.count != rhs.markers.count {
                return lhs.markers.count < rhs.markers.count
            }
            return pickPriority(lhs.path) > pickPriority(rhs.path)
        }) {
            return ChapterListChoice(markers: best.markers, path: best.path)
        }
        let singles = ranked.filter { $0.markers.count == 1 && !isDummySpan($0.markers, duration: duration) }
        if let best = singles.min(by: { pickPriority($0.path) < pickPriority($1.path) }) {
            return ChapterListChoice(markers: best.markers, path: best.path)
        }
        return ChapterListChoice(markers: [], path: .synthetic)
    }

    static func parseChapters(files: [URL], bookTitle: String) async -> [ChapterMarker] {
        var offset: TimeInterval = 0
        var all: [ChapterMarker] = []
        var anyEmbedded = false

        for url in files {
            let asset = AVURLAsset(url: url)
            let duration = (try? await seconds(of: asset)) ?? 0
            let localeSnapshot = await chapterLocaleSnapshot(in: asset)
            let tracks = (try? await asset.load(.tracks)) ?? []
            let av = await embeddedChapters(in: asset, availableLocales: localeSnapshot.locales)
            let timed = await timedMetadataChapters(in: asset, tracks: tracks)
            let text = await textTrackChapters(url: url, tracks: tracks, duration: duration)
            let nero = await Task.detached {
                MP4ChapterParser.chapters(from: url)
            }.value
            let decision = pickBestChapterList(av: av, timed: timed, text: text, nero: nero, duration: duration)
            let chosenCount = decision.markers.isEmpty ? 1 : decision.markers.count
            let line = chapterLogLine(
                filename: url.lastPathComponent,
                av: av.count,
                timed: timed.count,
                text: text.count,
                nero: nero.count,
                chosen: chosenCount,
                path: decision.path,
                locales: localeSnapshot.count,
                tracks: mediaTypeSummary(tracks)
            )
            chapterLogger.info("\(line, privacy: .public)")
            chapterLogSink?(line)

            if decision.markers.isEmpty {
                let title = files.count == 1 ? bookTitle : FileOrdering.displayTitle(from: url.lastPathComponent)
                let source: ChapterSource = files.count == 1 ? .synthetic : .file
                all.append(ChapterMarker(title: title, start: offset, duration: duration, source: source))
            } else {
                anyEmbedded = true
                for marker in decision.markers {
                    var adjusted = marker
                    adjusted.start += offset
                    if adjusted.duration <= 0 {
                        adjusted.duration = max(0, duration - marker.start)
                    }
                    all.append(adjusted)
                }
            }
            offset += duration
        }

        all.sort { $0.start < $1.start }
        fillDurations(in: &all, total: offset)
        if all.isEmpty {
            all = [ChapterMarker(title: bookTitle, start: 0, duration: offset, source: .synthetic)]
        }
        if !anyEmbedded, files.count > 1 {
            // keep per-file titles
        }
        return all
    }

    /// Locales to ask AVFoundation for. Phone language is only the fallback when the file lists none.
    nonisolated static func chapterLocalesToQuery(available: [Locale], preferredLanguages: [String]) -> [Locale] {
        let source = available.isEmpty ? preferredLanguages.map { Locale(identifier: $0) } : available
        var seen = Set<String>()
        var unique: [Locale] = []
        for locale in source {
            if seen.insert(locale.identifier).inserted {
                unique.append(locale)
            }
        }
        return unique
    }

    /// Prefer the list with the most chapters. A list of two or more beats any single-marker list.
    nonisolated static func richestMarkers(_ lists: [[ChapterMarker]]) -> [ChapterMarker] {
        var best: [ChapterMarker] = []
        var bestRich = 0
        for list in lists {
            if list.count >= 2 {
                if list.count > bestRich {
                    bestRich = list.count
                    best = list
                }
            } else if bestRich == 0, list.count > best.count {
                best = list
            }
        }
        return best
    }

    /// Audio `.chapterList` associations win. An empty association list falls back to every text-like track.
    nonisolated static func chapterTextTrackIDsToRead(associated: [Int], candidates: [Int]) -> [Int] {
        let source = associated.isEmpty ? candidates : associated
        var seen = Set<Int>()
        return source.filter { seen.insert($0).inserted }
    }

    nonisolated static func decodeChapterTextSample(_ data: Data, index: Int) -> String {
        let prefixed = lengthPrefixedTitle(data)
        let utf8 = utf8Title(data)
        let chosen: String?
        if let utf8, prefixed == nil {
            chosen = utf8
        } else if let prefixed, utf8 == nil || prefixOwnsBuffer(data) {
            chosen = prefixed
        } else if let utf8 {
            chosen = utf8
        } else if let utf16 = utf16Title(data) {
            chosen = utf16
        } else if let prefixed {
            chosen = prefixed
        } else {
            chosen = nil
        }
        guard let chosen else { return "Chapter \(max(1, index))" }
        let capped = String(chosen.prefix(titleCap))
        return capped.isEmpty ? "Chapter \(max(1, index))" : capped
    }

    nonisolated static func markers(
        fromTextSamples samples: [(start: TimeInterval, payload: Data)],
        duration: TimeInterval
    ) -> [ChapterMarker] {
        var kept: [(title: String, start: TimeInterval)] = []
        for sample in samples.prefix(sampleCap) {
            let start = sample.start
            guard start.isFinite, start >= 0 else { continue }
            if duration > 0, start > duration + 1 { continue }
            if let last = kept.last, start < last.start { continue }
            let title = decodeChapterTextSample(sample.payload, index: kept.count + 1)
            kept.append((title, start))
        }
        var markers: [ChapterMarker] = []
        markers.reserveCapacity(kept.count)
        for (index, item) in kept.enumerated() {
            let span: TimeInterval
            if index + 1 < kept.count {
                span = max(0, kept[index + 1].start - item.start)
            } else {
                span = 0
            }
            markers.append(ChapterMarker(title: item.title, start: item.start, duration: span, source: .embedded))
        }
        return markers
    }

    private nonisolated static func pickPriority(_ path: ChapterPickPath) -> Int {
        switch path {
        case .av: return 0
        case .textTrack: return 1
        case .nero: return 2
        case .timed: return 3
        case .synthetic: return 4
        }
    }

    private nonisolated static func sanitize(_ markers: [ChapterMarker], duration: TimeInterval) -> [ChapterMarker] {
        var kept: [ChapterMarker] = []
        for marker in markers {
            let start = marker.start
            guard start.isFinite, start >= 0 else { continue }
            if duration > 0, start > duration + 1 { continue }
            if let last = kept.last, start < last.start { continue }
            var copy = marker
            let trimmed = marker.title.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.title = trimmed.isEmpty ? "Chapter \(kept.count + 1)" : trimmed
            kept.append(copy)
        }
        return kept
    }

    /// One marker that covers the whole file, or a single hit at t≈0 with no duration.
    /// Title is irrelevant; the range is what blocks a richer Nero table.
    private nonisolated static func isDummySpan(_ markers: [ChapterMarker], duration: TimeInterval) -> Bool {
        guard markers.count == 1, let marker = markers.first else { return false }
        guard marker.start.isFinite, marker.start <= 1 else { return false }
        if !marker.duration.isFinite || marker.duration <= 0.5 { return true }
        guard duration > 0 else { return false }
        return marker.start + marker.duration >= duration - 1
    }

    private static func chapterLocaleSnapshot(in asset: AVAsset) async -> (locales: [Locale], count: Int) {
        if let locales = try? await asset.load(.availableChapterLocales) {
            return (locales, locales.count)
        }
        return ([], -1)
    }

    private static func embeddedChapters(in asset: AVAsset, availableLocales: [Locale]) async -> [ChapterMarker] {
        let locales = chapterLocalesToQuery(available: availableLocales, preferredLanguages: Locale.preferredLanguages)
        var lists: [[ChapterMarker]] = []
        for locale in locales {
            guard let groups = try? await asset.loadChapterMetadataGroups(
                withTitleLocale: locale,
                containingItemsWithCommonKeys: [.commonKeyTitle, .commonKeyArtwork]
            ), !groups.isEmpty else { continue }
            lists.append(await markers(from: groups))
        }
        var best = richestMarkers(lists)
        if best.isEmpty {
            let languages = Locale.preferredLanguages
            if let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages),
               !groups.isEmpty {
                best = await markers(from: groups)
            }
        }
        return best
    }

    private static func markers(from groups: [AVTimedMetadataGroup]) async -> [ChapterMarker] {
        var markers: [ChapterMarker] = []
        for (index, group) in groups.enumerated() {
            let start = group.timeRange.start.seconds
            let duration = group.timeRange.duration.seconds
            let titleItems = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle)
            let title = await stringValue(from: titleItems.first) ?? "Chapter \(index + 1)"
            markers.append(ChapterMarker(title: title, start: start, duration: duration, source: .embedded))
        }
        return markers
    }

    private static func timedMetadataChapters(in asset: AVAsset, tracks: [AVAssetTrack]) async -> [ChapterMarker] {
        var markers: [ChapterMarker] = []
        for track in tracks where track.mediaType == .metadata || track.mediaType == .text {
            guard let last = try? await track.load(.timeRange) else { continue }
            _ = last
        }
        if let metadata = try? await asset.load(.metadata) {
            let chapterish = metadata.filter { item in
                let id = item.identifier?.rawValue.lowercased() ?? ""
                return id.contains("chapter")
            }
            for (index, item) in chapterish.enumerated() {
                let time = item.time.seconds
                let title = await stringValue(from: item) ?? "Chapter \(index + 1)"
                if time.isFinite, time >= 0 {
                    markers.append(ChapterMarker(title: title, start: time, duration: 0, source: .embedded))
                }
            }
        }
        return markers
    }

    private static func textTrackChapters(url: URL, tracks: [AVAssetTrack], duration: TimeInterval) async -> [ChapterMarker] {
        var associated: [Int] = []
        for track in tracks where track.mediaType == .audio {
            guard let linked = try? await track.loadAssociatedTracks(ofType: .chapterList) else { continue }
            associated.append(contentsOf: linked.map { Int($0.trackID) })
        }
        var candidates: [Int] = []
        for track in tracks {
            if await isTextLike(track) {
                candidates.append(Int(track.trackID))
            }
        }
        let ids = chapterTextTrackIDsToRead(associated: associated, candidates: candidates)
        var lists: [[ChapterMarker]] = []
        for id in ids {
            let trackID = CMPersistentTrackID(id)
            let samples = await Task.detached {
                await readTextSamples(url: url, trackID: trackID)
            }.value
            let markers = markers(fromTextSamples: samples, duration: duration)
            if !markers.isEmpty {
                lists.append(markers)
            }
        }
        return richestMarkers(lists)
    }

    private static func isTextLike(_ track: AVAssetTrack) async -> Bool {
        switch track.mediaType {
        case .text, .closedCaption, .subtitle, .metadata:
            return true
        default:
            break
        }
        guard let formats = try? await track.load(.formatDescriptions) else { return false }
        for format in formats {
            let subtype = CMFormatDescriptionGetMediaSubType(format)
            if subtype == qtTextSubtype || subtype == tx3gSubtype || subtype == c608Subtype {
                return true
            }
        }
        return false
    }

    private nonisolated static func readTextSamples(url: URL, trackID: CMPersistentTrackID) async -> [(start: TimeInterval, payload: Data)] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks),
              let track = tracks.first(where: { $0.trackID == trackID }) else { return [] }
        if track.mediaType == .audio || track.mediaType == .video { return [] }
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }
            var samples: [(start: TimeInterval, payload: Data)] = []
            var finished = false
            while samples.count < sampleCap, !finished {
                let step: TextSampleStep = autoreleasepool {
                    guard let buffer = output.copyNextSampleBuffer() else { return .done }
                    let start = CMTimeGetSeconds(CMSampleBufferGetOutputPresentationTimeStamp(buffer))
                    guard start.isFinite, start >= 0, let payload = payloadData(from: buffer) else { return .skip }
                    return .sample(start, payload)
                }
                switch step {
                case .done:
                    finished = true
                case .skip:
                    continue
                case .sample(let start, let payload):
                    samples.append((start: start, payload: payload))
                }
            }
            if reader.status == .failed { return [] }
            return samples
        } catch {
            return []
        }
    }

    private nonisolated enum TextSampleStep {
        case sample(TimeInterval, Data)
        case skip
        case done
    }

    private nonisolated static func payloadData(from sample: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        let capped = min(length, 16_384)
        var bytes = [UInt8](repeating: 0, count: capped)
        let status = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: capped, destination: &bytes)
        guard status == kCMBlockBufferNoErr else { return nil }
        return Data(bytes)
    }

    private static func mediaTypeSummary(_ tracks: [AVAssetTrack]) -> String {
        var seen = Set<String>()
        var types: [String] = []
        for track in tracks {
            let raw = track.mediaType.rawValue
            if seen.insert(raw).inserted {
                types.append(raw)
            }
        }
        return types.joined(separator: ",")
    }

    private static func fillDurations(in markers: inout [ChapterMarker], total: TimeInterval) {
        guard !markers.isEmpty else { return }
        for i in 0..<markers.count {
            let nextStart = i + 1 < markers.count ? markers[i + 1].start : total
            if markers[i].duration <= 0.5 {
                markers[i].duration = max(0, nextStart - markers[i].start)
            }
        }
    }

    private static func seconds(of asset: AVAsset) async throws -> TimeInterval {
        let duration = try await asset.load(.duration)
        let value = duration.seconds
        return value.isFinite ? max(0, value) : 0
    }

    private static func stringValue(in items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> String? {
        let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
        return await stringValue(from: matches.first)
    }

    private static func dataValue(in items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> Data? {
        let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
        if let item = matches.first {
            if let data = try? await item.load(.dataValue) { return data }
            if let value = try? await item.load(.value) {
                if let data = value as? Data { return data }
                if let image = value as? NSData { return image as Data }
            }
        }
        return nil
    }

    private static func stringValue(from item: AVMetadataItem?) async -> String? {
        guard let item else { return nil }
        if let string = try? await item.load(.stringValue), !string.isEmpty { return string }
        if let value = try? await item.load(.value) as? String, !value.isEmpty { return value }
        return nil
    }

    private nonisolated static func utf8Title(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let cleaned = cleanedTitle(raw)
        guard isReasonableChapterTitle(cleaned) else { return nil }
        return cleaned
    }

    private nonisolated static func utf16Title(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        if data[0] == 0xFE, data[1] == 0xFF {
            return reasonableUTF16(data, encoding: .utf16BigEndian, skippingBOM: true)
        }
        if data[0] == 0xFF, data[1] == 0xFE {
            return reasonableUTF16(data, encoding: .utf16LittleEndian, skippingBOM: true)
        }
        guard data.count % 2 == 0 else { return nil }
        let big = reasonableUTF16(data, encoding: .utf16BigEndian, skippingBOM: false)
        let little = reasonableUTF16(data, encoding: .utf16LittleEndian, skippingBOM: false)
        switch (big, little) {
        case let (big?, little?):
            return textScore(little) > textScore(big) ? little : big
        case let (big?, nil):
            return big
        case let (nil, little?):
            return little
        case (nil, nil):
            return nil
        }
    }

    private nonisolated static func reasonableUTF16(_ data: Data, encoding: String.Encoding, skippingBOM: Bool) -> String? {
        let slice: Data
        if skippingBOM, data.count >= 4 {
            slice = data.subdata(in: 2..<data.count)
        } else {
            slice = data
        }
        guard let raw = String(data: slice, encoding: encoding) else { return nil }
        let cleaned = cleanedTitle(raw)
        guard isReasonableChapterTitle(cleaned) else { return nil }
        return cleaned
    }

    private nonisolated static func lengthPrefixedTitle(_ data: Data) -> String? {
        guard data.count >= 3 else { return nil }
        let length = (Int(data[0]) << 8) | Int(data[1])
        guard length > 0, length <= 2_048, 2 + length <= data.count else { return nil }
        let slice = data.subdata(in: 2..<(2 + length))
        if let utf8 = utf8Title(slice) { return utf8 }
        if let utf16 = utf16Title(slice) { return utf16 }
        return nil
    }

    /// A 16-bit length owns the buffer when it consumes the sample, or the tail is QuickTime atoms (`encd`, `styl`).
    private nonisolated static func prefixOwnsBuffer(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let length = (Int(data[0]) << 8) | Int(data[1])
        let textEnd = 2 + length
        guard length > 0, textEnd <= data.count else { return false }
        if textEnd == data.count { return true }
        return looksLikeAtoms(data.subdata(in: textEnd..<data.count))
    }

    private nonisolated static func looksLikeAtoms(_ data: Data) -> Bool {
        var index = 0
        var found = false
        while index + 8 <= data.count {
            let size = (Int(data[index]) << 24)
                | (Int(data[index + 1]) << 16)
                | (Int(data[index + 2]) << 8)
                | Int(data[index + 3])
            let type = data[(index + 4)..<(index + 8)]
            guard type.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return false }
            guard size >= 8, index + size <= data.count else { return false }
            index += size
            found = true
        }
        return found && index == data.count
    }

    private nonisolated static func cleanedTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isReasonableChapterTitle(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }
        for scalar in title.unicodeScalars {
            if scalar.value == 0xFFFD { return false }
            if scalar.value < 32, scalar != "\n", scalar != "\t", scalar != "\r" { return false }
        }
        return true
    }

    private nonisolated static func textScore(_ title: String) -> Int {
        var score = 0
        for scalar in title.unicodeScalars {
            if (scalar.value >= 32 && scalar.value < 127) || (scalar.value >= 0xC0 && scalar.value <= 0x24F) {
                score += 2
            } else {
                score += 1
            }
        }
        return score
    }
}
