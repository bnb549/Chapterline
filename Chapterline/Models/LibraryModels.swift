import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var narrator: String?
    var sourceFilename: String
    var addedAt: Date
    var lastPlayedAt: Date?
    var duration: TimeInterval
    var isFinished: Bool
    var playbackRate: Double
    var position: TimeInterval
    var lastPauseAt: Date?
    var artworkOverridePath: String?
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \BookFile.book)
    var files: [BookFile]

    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter]

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "Unknown Author",
        narrator: String? = nil,
        sourceFilename: String,
        addedAt: Date = Date(),
        duration: TimeInterval = 0,
        playbackRate: Double = 1.0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.narrator = narrator
        self.sourceFilename = sourceFilename
        self.addedAt = addedAt
        self.duration = duration
        self.isFinished = false
        self.playbackRate = playbackRate
        self.position = 0
        self.files = []
        self.chapters = []
        self.bookmarks = []
    }

    var sortedFiles: [BookFile] {
        files.sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedChapters: [Chapter] {
        chapters.sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedBookmarks: [Bookmark] {
        bookmarks.sorted { $0.createdAt > $1.createdAt }
    }

    var progress: Double {
        TimeMath.progress(duration: duration, position: position)
    }

    var remainingAtRate: TimeInterval {
        TimeMath.remaining(duration: duration, position: position, rate: playbackRate)
    }

    var chapterMarkers: [ChapterMarker] {
        sortedChapters.map {
            ChapterMarker(title: $0.title, start: $0.start, duration: $0.duration, source: $0.source)
        }
    }

    var currentChapter: Chapter? {
        let markers = chapterMarkers
        guard !markers.isEmpty else { return nil }
        let index = TimeMath.chapterIndex(at: position, in: markers)
        let sorted = sortedChapters
        guard sorted.indices.contains(index) else { return nil }
        return sorted[index]
    }
}

@Model
final class BookFile {
    var relativePath: String
    var sortIndex: Int
    var duration: TimeInterval
    var book: Book?

    init(relativePath: String, sortIndex: Int, duration: TimeInterval) {
        self.relativePath = relativePath
        self.sortIndex = sortIndex
        self.duration = duration
    }
}

@Model
final class Chapter {
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
    var sortIndex: Int
    var sourceRaw: String
    var book: Book?

    init(title: String, start: TimeInterval, duration: TimeInterval, sortIndex: Int, source: ChapterSource) {
        self.title = title
        self.start = start
        self.duration = duration
        self.sortIndex = sortIndex
        self.sourceRaw = source.rawValue
    }

    var source: ChapterSource {
        ChapterSource(rawValue: sourceRaw) ?? .synthetic
    }
}

@Model
final class Bookmark {
    var createdAt: Date
    var position: TimeInterval
    var chapterStart: TimeInterval?
    var note: String?
    var book: Book?

    init(position: TimeInterval, chapterStart: TimeInterval?, note: String? = nil, createdAt: Date = Date()) {
        self.createdAt = createdAt
        self.position = position
        self.chapterStart = chapterStart
        self.note = note
    }
}

@Model
final class Folder {
    var name: String
    var sortIndex: Int
    @Relationship(inverse: \Book.folder)
    var books: [Book]

    init(name: String, sortIndex: Int) {
        self.name = name
        self.sortIndex = sortIndex
        self.books = []
    }
}
