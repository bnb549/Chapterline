import Foundation
import SwiftData

enum SessionEndReason: String, Codable, Equatable, Sendable, CaseIterable {
    case pause
    case sleepTimer
    case skipAway
    case finished
    case interruption
    case background
    case routeChange
    case unknown
}

/// Listening history is independent of `Book` so deleting a title does not erase hours.
@Model
final class ListeningSession {
    var id: UUID
    var bookID: UUID
    var bookTitle: String
    var author: String
    var narrator: String?
    var startedAt: Date
    var endedAt: Date
    var wallDuration: TimeInterval
    var contentDuration: TimeInterval
    var rate: Double
    var startPosition: TimeInterval
    var endPosition: TimeInterval
    var chapterTitle: String
    var endReasonRaw: String
    var counted: Bool

    init(
        id: UUID = UUID(),
        bookID: UUID,
        bookTitle: String,
        author: String,
        narrator: String? = nil,
        startedAt: Date,
        endedAt: Date,
        wallDuration: TimeInterval,
        contentDuration: TimeInterval,
        rate: Double,
        startPosition: TimeInterval,
        endPosition: TimeInterval,
        chapterTitle: String,
        endReason: SessionEndReason,
        counted: Bool = true
    ) {
        self.id = id
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.author = author
        self.narrator = narrator
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wallDuration = wallDuration
        self.contentDuration = contentDuration
        self.rate = rate
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.chapterTitle = chapterTitle
        self.endReasonRaw = endReason.rawValue
        self.counted = counted
    }

    var endReason: SessionEndReason {
        get { SessionEndReason(rawValue: endReasonRaw) ?? .unknown }
        set { endReasonRaw = newValue.rawValue }
    }
}
