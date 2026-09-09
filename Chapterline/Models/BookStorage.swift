import Foundation

enum BookStorage {
    static let appSupportFolderName = "Chapterline"
    static let storeFilename = "Chapterline.store"
    static let booksFolderName = "Books"

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static var storeURL: URL {
        applicationSupport.appendingPathComponent(storeFilename)
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var booksRoot: URL {
        documents.appendingPathComponent(booksFolderName, isDirectory: true)
    }

    static func directory(for bookID: UUID) -> URL {
        booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    static func ensureLibraryFolders() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fm.createDirectory(at: booksRoot, withIntermediateDirectories: true)
    }

    static func ensureDirectory(for bookID: UUID) throws -> URL {
        try ensureLibraryFolders()
        let url = directory(for: bookID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeDirectory(for bookID: UUID) {
        let url = directory(for: bookID)
        try? FileManager.default.removeItem(at: url)
    }

    static func fileURL(bookID: UUID, relativePath: String) -> URL {
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
