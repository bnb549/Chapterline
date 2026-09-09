import Foundation
import UniformTypeIdentifiers
import ZIPFoundation

enum ImportPipeline {
    struct Plan: Sendable {
        var audioFiles: [URL]
        var blocked: [URL]
        var needsDecision: Bool
    }

    static func plan(urls: [URL]) async throws -> Plan {
        var audio: [URL] = []
        var blocked: [URL] = []
        for url in urls {
            if DRMGuard.isBlocked(url) {
                blocked.append(url)
                continue
            }
            if AudioFileFilter.isZip(url) {
                let extracted = try unzip(url)
                for item in extracted {
                    if DRMGuard.isBlocked(item) {
                        blocked.append(item)
                    } else if AudioFileFilter.isPlayableAudio(item) {
                        audio.append(item)
                    }
                }
            } else if AudioFileFilter.isPlayableAudio(url) {
                audio.append(url)
            } else if isDirectory(url) {
                let nested = audioFiles(inDirectory: url)
                audio.append(contentsOf: nested.audio)
                blocked.append(contentsOf: nested.blocked)
            }
        }
        audio = FileOrdering.combineSort(audio)
        let needsDecision = audio.count > 1
        return Plan(audioFiles: audio, blocked: blocked, needsDecision: needsDecision)
    }

    static func unzip(_ url: URL) throws -> [URL] {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapterline-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // ZIPFoundation: unzip import; Apple has no Zip API.
        try FileManager.default.unzipItem(at: url, to: destination)
        let nested = audioFiles(inDirectory: destination)
        if nested.audio.isEmpty && nested.blocked.isEmpty {
            throw ImportError.emptyZip
        }
        return nested.audio + nested.blocked
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func audioFiles(inDirectory directory: URL) -> (audio: [URL], blocked: [URL]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return ([], [])
        }
        var audio: [URL] = []
        var blocked: [URL] = []
        for case let file as URL in enumerator {
            if DRMGuard.isBlocked(file) {
                blocked.append(file)
            } else if AudioFileFilter.isPlayableAudio(file) {
                audio.append(file)
            }
        }
        return (FileOrdering.combineSort(audio), blocked)
    }
}

enum AudioUTTypes {
    static var importTypes: [UTType] {
        var types: [UTType] = [.mp3, .mpeg4Audio, .aiff, .wav, .zip]
        if let m4b = UTType(filenameExtension: "m4b") { types.append(m4b) }
        if let appleM4B = UTType("com.apple.m4b-audio") { types.append(appleM4B) }
        if let aac = UTType(filenameExtension: "aac") { types.append(aac) }
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        types.append(.audio)
        return types
    }
}
