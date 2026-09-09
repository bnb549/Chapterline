import Foundation

struct PlayerSnapshot: Equatable, Sendable {
    var bookID: UUID?
    var title: String
    var author: String
    var narrator: String?
    var chapterTitle: String
    var chapterIndex: Int
    var chapterStart: TimeInterval
    var chapterDuration: TimeInterval
    var position: TimeInterval
    var duration: TimeInterval
    var rate: Double
    var isPlaying: Bool
    var volume: Float
    var boost: Float
    var sleepEndsAt: Date?
    var sleepFading: Bool
    var chapters: [ChapterMarker]
    var fileDurations: [TimeInterval]

    static let empty = PlayerSnapshot(
        bookID: nil,
        title: "",
        author: "",
        narrator: nil,
        chapterTitle: "",
        chapterIndex: 0,
        chapterStart: 0,
        chapterDuration: 0,
        position: 0,
        duration: 0,
        rate: 1,
        isPlaying: false,
        volume: 1,
        boost: 1,
        sleepEndsAt: nil,
        sleepFading: false,
        chapters: [],
        fileDurations: []
    )

    var remaining: TimeInterval {
        TimeMath.remaining(duration: duration, position: position, rate: rate)
    }

    var chapterRemaining: TimeInterval {
        TimeMath.remaining(duration: chapterStart + chapterDuration, position: position, rate: rate)
    }

    var progress: Double {
        TimeMath.progress(duration: duration, position: position)
    }

    var sleepRemaining: TimeInterval? {
        guard let sleepEndsAt else { return nil }
        return max(0, sleepEndsAt.timeIntervalSinceNow)
    }
}

struct LoadedBook: Sendable {
    var id: UUID
    var title: String
    var author: String
    var narrator: String?
    var fileURLs: [URL]
    var fileDurations: [TimeInterval]
    var chapters: [ChapterMarker]
    var artworkData: Data?
    var rate: Double
    var startPosition: TimeInterval
}
