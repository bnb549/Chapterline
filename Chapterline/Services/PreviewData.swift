import Foundation
import SwiftData
import SwiftUI

enum PreviewData {
    static func mockContainer() -> ModelContainer {
        let container = Persistence.inMemory()
        let context = ModelContext(container)
        seed(into: context)
        return container
    }

    static func seed(into context: ModelContext) {
        let reading = Folder(name: "Currently Reading", sortIndex: 0)
        let series = Folder(name: "Series", sortIndex: 1)
        context.insert(reading)
        context.insert(series)

        let dune = makeBook(
            title: "Dune",
            author: "Frank Herbert",
            narrator: "Scott Brick",
            duration: 21 * 3600 + 2 * 60,
            position: 3 * 3600 + 14 * 60,
            rate: 1.2,
            chapters: [
                ("Book One", 0, 5400),
                ("Muad'Dib", 5400, 7200),
                ("The Prophet", 12600, 9000),
                ("Appendix", 21600, 6120)
            ]
        )
        dune.lastPlayedAt = Date().addingTimeInterval(-3600)
        dune.folder = reading

        let pride = makeBook(
            title: "Pride and Prejudice",
            author: "Jane Austen",
            duration: 11 * 3600 + 35 * 60,
            position: 11 * 3600 + 30 * 60,
            rate: 1.0,
            chapters: [
                ("Chapter 1", 0, 1200),
                ("Chapter 2", 1200, 1500),
                ("Chapter 3", 2700, 1800)
            ]
        )
        pride.isFinished = true
        pride.finishedAt = Date().addingTimeInterval(-86400)

        let leftHand = makeBook(
            title: "The Left Hand of Darkness",
            author: "Ursula K. Le Guin",
            narrator: "Gabra Zackman",
            duration: 9 * 3600 + 47 * 60,
            position: 42 * 60,
            rate: 1.6,
            chapters: [
                ("A Parade in Erhenrang", 0, 2400),
                ("The Place Inside the Blizzard", 2400, 3000),
                ("The Mad King", 5400, 2700)
            ]
        )
        leftHand.folder = series

        context.insert(dune)
        context.insert(pride)
        context.insert(leftHand)
        seedSessions(into: context, dune: dune, pride: pride, leftHand: leftHand)
        try? context.save()
    }

    private static func seedSessions(into context: ModelContext, dune: Book, pride: Book, leftHand: Book) {
        let calendar = Calendar.current
        let today = Date()
        func day(_ offset: Int, hour: Int, duration: TimeInterval, book: Book, rate: Double, chapter: String) {
            guard let started = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) else { return }
            let start = calendar.date(bySettingHour: hour, minute: 12, second: 0, of: started) ?? started
            let wall = duration
            let session = ListeningSession(
                bookID: book.id,
                bookTitle: book.title,
                author: book.author,
                narrator: book.narrator,
                startedAt: start,
                endedAt: start.addingTimeInterval(wall),
                wallDuration: wall,
                contentDuration: ListeningStatsMath.contentDuration(wall: wall, rate: rate),
                rate: rate,
                startPosition: 600,
                endPosition: 600 + wall * rate,
                chapterTitle: chapter,
                endReason: .pause
            )
            context.insert(session)
        }
        day(0, hour: 7, duration: 42 * 60, book: dune, rate: 1.2, chapter: "Muad'Dib")
        day(-1, hour: 21, duration: 55 * 60, book: dune, rate: 1.2, chapter: "Book One")
        day(-2, hour: 6, duration: 28 * 60, book: leftHand, rate: 1.6, chapter: "A Parade in Erhenrang")
        day(-4, hour: 19, duration: 90 * 60, book: pride, rate: 1.0, chapter: "Chapter 2")
        day(-8, hour: 8, duration: 35 * 60, book: dune, rate: 1.5, chapter: "The Prophet")
    }

    private static func makeBook(
        title: String,
        author: String,
        narrator: String? = nil,
        duration: TimeInterval,
        position: TimeInterval,
        rate: Double,
        chapters: [(String, TimeInterval, TimeInterval)]
    ) -> Book {
        let book = Book(
            title: title,
            author: author,
            narrator: narrator,
            sourceFilename: "\(title).m4b",
            duration: duration,
            playbackRate: rate
        )
        book.position = position
        let file = BookFile(relativePath: "audio.m4b", sortIndex: 0, duration: duration)
        file.book = book
        book.files = [file]
        for (index, chapter) in chapters.enumerated() {
            let record = Chapter(
                title: chapter.0,
                start: chapter.1,
                duration: chapter.2,
                sortIndex: index,
                source: .embedded
            )
            record.book = book
            book.chapters.append(record)
        }
        return book
    }
}

#if DEBUG
enum PreviewSupport {
    @MainActor
    static func library() -> LibraryStore {
        LibraryStore(container: PreviewData.mockContainer())
    }
}
#endif
