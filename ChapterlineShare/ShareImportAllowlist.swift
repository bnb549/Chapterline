import UniformTypeIdentifiers

/// Audiobook, audio, and zip types Chapterline actually imports.
/// Info.plist `NSExtensionActivationRule` is the share-sheet gate and cannot call Swift,
/// so the same six UTIs are duplicated in that predicate.
enum ShareImportAllowlist: Sendable {
    nonisolated static let typeIdentifiers: [String] = [
        "public.mpeg-4-audio",
        "public.mp3",
        "public.aac-audio",
        "public.zip-archive",
        "org.xiph.flac",
        "com.apple.m4b-audio"
    ]

    nonisolated static let pathExtensions: Set<String> = [
        "m4b", "m4a", "mp3", "aac", "flac", "zip"
    ]

    nonisolated static let maxAttachmentCount = 20

    nonisolated static func allows(typeIdentifier: String) -> Bool {
        if typeIdentifiers.contains(typeIdentifier) { return true }
        guard let type = UTType(typeIdentifier) else { return false }
        for identifier in typeIdentifiers {
            guard let allowed = UTType(identifier) else { continue }
            if type.conforms(to: allowed) { return true }
        }
        return false
    }

    nonisolated static func allows(pathExtension: String) -> Bool {
        pathExtensions.contains(pathExtension.lowercased())
    }

    /// A file URL is kept when its type identifier or its path extension is on the allowlist.
    nonisolated static func allowsFile(typeIdentifiers identifiers: [String], pathExtension: String) -> Bool {
        if identifiers.contains(where: { allows(typeIdentifier: $0) }) { return true }
        return allows(pathExtension: pathExtension)
    }
}
