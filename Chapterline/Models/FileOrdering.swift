import Foundation

enum FileOrdering: Sendable {
    /// Numeric-aware filename sort used when combining a folder or zip of files into one book.
    nonisolated static func combineSort(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    nonisolated static func combineSortNames(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    nonisolated static func displayTitle(from filename: String) -> String {
        let stripped = (filename as NSString).deletingPathExtension
        return stripped
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DRMGuard: Sendable {
    nonisolated static let blockedExtensions: Set<String> = ["aa", "aax"]

    nonisolated static func isBlocked(_ url: URL) -> Bool {
        isBlocked(extension: url.pathExtension)
    }

    nonisolated static func isBlocked(extension ext: String) -> Bool {
        blockedExtensions.contains(ext.lowercased())
    }

    nonisolated static let rejectionMessage = "Chapterline plays DRM-free files only. Audible .aa and .aax are not supported."
}

enum AudioFileFilter: Sendable {
    nonisolated static let playableExtensions: Set<String> = [
        "m4b", "m4a", "mp3", "aac", "flac", "wav", "aiff", "aif", "caf"
    ]

    nonisolated static func isPlayableAudio(_ url: URL) -> Bool {
        playableExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func isZip(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }
}
