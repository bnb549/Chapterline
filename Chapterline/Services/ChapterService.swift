import AVFoundation
import Foundation

struct BookMetadata: Sendable {
    var title: String?
    var author: String?
    var narrator: String?
    var artwork: Data?
    var duration: TimeInterval
}

enum ChapterService {
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

    static func parseChapters(files: [URL], bookTitle: String) async -> [ChapterMarker] {
        var offset: TimeInterval = 0
        var all: [ChapterMarker] = []
        var anyEmbedded = false

        for (index, url) in files.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = (try? await seconds(of: asset)) ?? 0
            var markers = await embeddedChapters(in: asset)
            if markers.isEmpty {
                markers = await timedMetadataChapters(in: asset)
            }
            if markers.isEmpty {
                markers = MP4ChapterParser.chapters(from: url)
            }
            if markers.isEmpty {
                let title = files.count == 1 ? bookTitle : FileOrdering.displayTitle(from: url.lastPathComponent)
                let source: ChapterSource = files.count == 1 ? .synthetic : .file
                all.append(ChapterMarker(title: title, start: offset, duration: duration, source: source))
            } else {
                anyEmbedded = true
                for marker in markers {
                    var adjusted = marker
                    adjusted.start += offset
                    if adjusted.duration <= 0 {
                        adjusted.duration = max(0, duration - marker.start)
                    }
                    all.append(adjusted)
                }
            }
            offset += duration
            _ = index
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
