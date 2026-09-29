import AVFoundation
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
    case timed
    case nero
    case synthetic
}

nonisolated struct ChapterListChoice: Equatable, Sendable {
    var markers: [ChapterMarker]
    var path: ChapterPickPath
}

enum ChapterService {
    private static let chapterLogger = Logger(subsystem: "com.benmonroe.free-player", category: "chapters")

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
        nero: Int,
        chosen: Int,
        path: ChapterPickPath
    ) -> String {
        "chapters url=\(filename) av=\(av) timed=\(timed) nero=\(nero) chosen=\(chosen) path=\(path.rawValue)"
    }

    nonisolated static func pickBestChapterList(
        av: [ChapterMarker],
        timed: [ChapterMarker],
        nero: [ChapterMarker],
        duration: TimeInterval
    ) -> ChapterListChoice {
        let avList = sanitize(av, duration: duration)
        let timedList = sanitize(timed, duration: duration)
        let neroList = sanitize(nero, duration: duration)
        let ranked: [(markers: [ChapterMarker], path: ChapterPickPath)] = [
            (avList, .av),
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
            let av = await embeddedChapters(in: asset)
            let timed = await timedMetadataChapters(in: asset)
            let nero = await Task.detached {
                MP4ChapterParser.chapters(from: url)
            }.value
            let decision = pickBestChapterList(av: av, timed: timed, nero: nero, duration: duration)
            let chosenCount = decision.markers.isEmpty ? 1 : decision.markers.count
            let line = chapterLogLine(
                filename: url.lastPathComponent,
                av: av.count,
                timed: timed.count,
                nero: nero.count,
                chosen: chosenCount,
                path: decision.path
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

    private nonisolated static func pickPriority(_ path: ChapterPickPath) -> Int {
        switch path {
        case .av: return 0
        case .nero: return 1
        case .timed: return 2
        case .synthetic: return 3
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

    private static func embeddedChapters(in asset: AVAsset) async -> [ChapterMarker] {
        let languages = Locale.preferredLanguages
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages),
              !groups.isEmpty else { return [] }
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

    private static func timedMetadataChapters(in asset: AVAsset) async -> [ChapterMarker] {
        guard let tracks = try? await asset.load(.tracks) else { return [] }
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
}
