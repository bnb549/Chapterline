import Foundation

enum BookStorage {
    static let appSupportFolderName = "Chapterline"
    static let storeFilename = "Chapterline.store"
    static let booksFolderName = "Books"

    nonisolated static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    nonisolated static var storeURL: URL {
        applicationSupport.appendingPathComponent(storeFilename)
    }

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    nonisolated static var booksRoot: URL {
        documents.appendingPathComponent(booksFolderName, isDirectory: true)
    }

    nonisolated static func directory(for bookID: UUID) -> URL {
        booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    nonisolated static func ensureLibraryFolders() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fm.createDirectory(at: booksRoot, withIntermediateDirectories: true)
    }

    nonisolated static func ensureDirectory(for bookID: UUID) throws -> URL {
        try ensureLibraryFolders()
        let url = directory(for: bookID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated static func removeDirectory(for bookID: UUID) {
        let url = directory(for: bookID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Relocate a staging import folder onto a reused bookID. Caller must not pass a live book's ID.
    nonisolated static func moveDirectory(from sourceID: UUID, to destID: UUID) throws {
        guard sourceID != destID else { return }
        let fm = FileManager.default
        let source = directory(for: sourceID)
        let dest = directory(for: destID)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: dest)
    }

    nonisolated static func uniqueFilename(_ name: String, in directory: URL) -> String {
        var candidate = name
        var step = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base)-\(step)" : "\(base)-\(step).\(ext)"
            step += 1
        }
        return candidate
    }

    nonisolated static func fileURL(bookID: UUID, relativePath: String) -> URL {
        directory(for: bookID).appendingPathComponent(relativePath)
    }

    static let embeddedCoverName = "cover-embedded.jpg"
    static let overrideCoverName = "cover-override.jpg"
    static let folderCoverNames = ["cover.jpg", "cover.png", "folder.jpg", "folder.png"]
}

enum AppGroup {
    static let identifier = "group.com.benmonroe.free-player"
    static let inboxFolder = "Inbox"
    static let snapshotFilename = "now-playing.json"
    static let darwinImport = "com.benmonroe.free-player.import"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var inboxURL: URL? {
        containerURL?.appendingPathComponent(inboxFolder, isDirectory: true)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFilename)
    }

    static func ensureInbox() -> URL? {
        guard let inboxURL else { return nil }
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        return inboxURL
    }
}

struct NowPlayingSnapshot: Codable, Equatable, Sendable {
    var bookID: UUID?
    var title: String
    var author: String
    var chapterTitle: String
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var rate: Double
    var coverRelativePath: String?
}
