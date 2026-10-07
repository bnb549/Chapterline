import SwiftData
import XCTest
@testable import Chapterline

final class BundledSampleTests: XCTestCase {
    func testEmptyLibraryDoesNotAlreadyContainTheSample() {
        let library = LibraryStore(container: Persistence.inMemory())
        XCTAssertFalse(library.containsBundledSample(filename: BundledSample.filename, title: BundledSample.title))
    }

    func testFilenameAndTitleMarksTheSamplePresent() throws {
        let library = LibraryStore(container: Persistence.inMemory())
        insert(library: library, title: "The Raven", filename: "TheRaven.m4b", identity: false)
        XCTAssertTrue(library.containsBundledSample(filename: "TheRaven.m4b", title: "The Raven"))
        XCTAssertFalse(library.containsBundledSample(filename: "TheRaven.m4b", title: "Something Else"))
        XCTAssertFalse(library.containsBundledSample(filename: "other.mp3", title: "The Raven"))
    }

    func testLiveIdentityMarksTheSamplePresentAfterARename() throws {
        let library = LibraryStore(container: Persistence.inMemory())
        insert(library: library, title: "Poem", filename: "TheRaven.m4b", identity: true)
        XCTAssertTrue(library.containsBundledSample(filename: BundledSample.filename, title: BundledSample.title))
    }

    func testDeletedSampleIsNotStillInTheLibrary() throws {
        let library = LibraryStore(container: Persistence.inMemory())
        insert(library: library, title: "The Raven", filename: "TheRaven.m4b", identity: true)
        let book = try XCTUnwrap(library.books.first)
        library.delete(book)
        XCTAssertTrue(library.books.isEmpty)
        XCTAssertFalse(library.containsBundledSample(filename: BundledSample.filename, title: BundledSample.title))
    }

    func testBundledSampleImportsAsTheRaven() async throws {
        let bundled = try XCTUnwrap(BundledSample.bundledURL(), "The Raven is missing from the app bundle")
        let library = LibraryStore(container: Persistence.inMemory())
        await library.handleIncomingURLs([bundled])
        XCTAssertNil(library.importError)
        XCTAssertEqual(library.books.count, 1)
        let book = try XCTUnwrap(library.books.first)
        XCTAssertEqual(book.title, "The Raven")
        XCTAssertEqual(book.author, "Edgar Allan Poe")
        XCTAssertEqual(book.position, 0, accuracy: 0.001)
        XCTAssertFalse(book.isFinished)
        XCTAssertGreaterThan(book.duration, 120)
        XCTAssertLessThan(book.duration, 1_200)
        XCTAssertTrue(library.containsBundledSample(filename: BundledSample.filename, title: BundledSample.title))
        library.delete(book)
    }

    private func insert(library: LibraryStore, title: String, filename: String, identity: Bool) {
        let context = ModelContext(library.container)
        let book = Book(title: title, author: "Edgar Allan Poe", sourceFilename: filename, duration: 571)
        let file = BookFile(relativePath: filename, sortIndex: 0, duration: 571)
        file.book = book
        book.files = [file]
        context.insert(book)
        if identity {
            context.insert(
                BookIdentity(
                    identityKey: "sample",
                    bookID: book.id,
                    title: "The Raven",
                    author: "Edgar Allan Poe",
                    duration: 571,
                    totalByteSize: 4_800_000,
                    sourceSignature: BookIdentityMath.sourceSignature(filenames: [filename])
                )
            )
        }
        try? context.save()
        library.refresh()
    }
}
