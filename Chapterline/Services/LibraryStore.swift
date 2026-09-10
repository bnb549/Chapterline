import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

@Observable
final class LibraryStore {
    var books: [Book] = []
    var folders: [Folder] = []
    var importProgress: ImportProgress?
    var importError: String?
    var pendingCombine: PendingCombine?
    var selectedFolderID: PersistentIdentifier?

    let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = true
        refresh()
        seedDefaultFoldersIfNeeded()
        refresh()
    }

    func refresh() {
        let bookDescriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let folderDescriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.sortIndex)])
        books = (try? context.fetch(bookDescriptor)) ?? []
        folders = (try? context.fetch(folderDescriptor)) ?? []
    }

    var continueListening: Book? {
        books
            .filter { !$0.isFinished && $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .first
    }

    func filteredBooks(search: String, folder: Folder?, sort: LibrarySort) -> [Book] {
        var items = books
        if let folder {
            items = items.filter { $0.folder?.persistentModelID == folder.persistentModelID }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.author.localizedCaseInsensitiveContains(query)
                    || $0.sourceFilename.localizedCaseInsensitiveContains(query)
                    || ($0.narrator?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        switch sort {
        case .recent:
            items.sort {
                ($0.lastPlayedAt ?? $0.addedAt) > ($1.lastPlayedAt ?? $1.addedAt)
            }
        case .author:
            items.sort {
                $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
                    || ($0.author.localizedCaseInsensitiveCompare($1.author) == .orderedSame
                        && $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending)
            }
        case .title:
            items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .progress:
            items.sort { $0.progress > $1.progress }
        }
        return items
    }

    func book(id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func updatePlayback(bookID: UUID, position: TimeInterval, rate: Double, isPlaying: Bool, finished: Bool) {
        guard let book = book(id: bookID) else { return }
        book.position = max(0, min(position, max(book.duration, position)))
        book.playbackRate = rate
        if isPlaying {
            book.lastPlayedAt = Date()
            book.lastPauseAt = nil
        } else {
            book.lastPauseAt = Date()
        }
        if finished {
            book.isFinished = true
            book.position = book.duration
            if book.finishedAt == nil {
                book.finishedAt = Date()
            }
        }
        save()
    }

    func markFinished(_ book: Book, finished: Bool) {
        book.isFinished = finished
        if finished {
            book.position = book.duration
            if book.finishedAt == nil {
                book.finishedAt = Date()
            }
        } else {
            book.finishedAt = nil
        }
        save()
        refresh()
    }

    func delete(_ book: Book) {
        let id = book.id
        persistIdentity(for: book)
        context.delete(book)
        save()
        BookStorage.removeDirectory(for: id)
        refresh()
    }

    func rename(_ book: Book, title: String, author: String, narrator: String?) {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNarrator = narrator?.trimmingCharacters(in: .whitespacesAndNewlines)
        book.narrator = (trimmedNarrator?.isEmpty ?? true) ? nil : trimmedNarrator
        save()
        refresh()
    }

    func move(_ book: Book, to folder: Folder?) {
        book.folder = folder
        save()
        refresh()
    }

    func addFolder(named name: String) {
        let folder = Folder(name: name, sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(folder)
        save()
        refresh()
    }

    func renameFolder(_ folder: Folder, to name: String) {
        folder.name = name
        save()
        refresh()
    }

    func deleteFolder(_ folder: Folder) {
        for book in folder.books { book.folder = nil }
        context.delete(folder)
        save()
        refresh()
    }

    func addBookmark(on book: Book, position: TimeInterval, chapterStart: TimeInterval?, note: String?) {
        let bookmark = Bookmark(position: position, chapterStart: chapterStart, note: note)
        bookmark.book = book
        book.bookmarks.append(bookmark)
        save()
        refresh()
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
        refresh()
    }

    func replaceChapters(on book: Book, with markers: [ChapterMarker]) {
        for chapter in book.chapters {
            context.delete(chapter)
        }
        for (index, marker) in markers.enumerated() {
            let chapter = Chapter(
                title: marker.title,
                start: marker.start,
                duration: marker.duration,
                sortIndex: index,
                source: marker.source
            )
            chapter.book = book
            book.chapters.append(chapter)
        }
        save()
        refresh()
    }

    func save() {
        do {
            try context.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    func handleIncomingURLs(_ urls: [URL]) async {
        let scoped = urls.map { url -> URL in
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        defer {
            for url in urls { url.stopAccessingSecurityScopedResource() }
        }
        await importFiles(scoped)
    }

    func drainShareInbox() async {
        guard let inbox = AppGroup.ensureInbox() else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        guard !contents.isEmpty else { return }
        await importFiles(contents)
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func importFiles(_ urls: [URL]) async {
        importError = nil
        do {
            let plan = try await ImportPipeline.plan(urls: urls)
            if !plan.blocked.isEmpty && plan.audioFiles.isEmpty && plan.needsDecision == false {
                importError = DRMGuard.rejectionMessage
                return
            }
            if plan.needsDecision {
                pendingCombine = PendingCombine(urls: plan.audioFiles, blocked: plan.blocked)
                return
            }
            try await performImport(plan.audioFiles, combine: plan.audioFiles.count > 1)
        } catch {
            importError = error.localizedDescription
        }
    }

    func resolvePendingCombine(_ combine: Bool) async {
        guard let pending = pendingCombine else { return }
        pendingCombine = nil
        do {
            try await performImport(pending.urls, combine: combine)
        } catch {
            importError = error.localizedDescription
        }
    }

    func reloadChapters(for book: Book) async {
        let urls = book.sortedFiles.map { BookStorage.fileURL(bookID: book.id, relativePath: $0.relativePath) }
        let markers = await ChapterService.parseChapters(files: urls, bookTitle: book.title)
        replaceChapters(on: book, with: markers)
    }

    private func performImport(_ urls: [URL], combine: Bool) async throws {
        guard !urls.isEmpty else { return }
        if combine {
            try await importCombined(urls)
        } else {
            for (index, url) in urls.enumerated() {
                await MainActor.run {
                    importProgress = ImportProgress(
                        fraction: Double(index) / Double(urls.count),
                        message: "Importing \(url.lastPathComponent)"
                    )
                }
                try await importSingle(url)
            }
        }
        await MainActor.run {
            importProgress = nil
            refresh()
        }
    }

    private func importSingle(_ url: URL) async throws {
        if DRMGuard.isBlocked(url) {
            throw ImportError.drm
        }
        let stagingID = UUID()
        let directory = try BookStorage.ensureDirectory(for: stagingID)
        let filename = BookStorage.uniqueFilename(url.lastPathComponent, in: directory)
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: url, to: destination)

        await MainActor.run {
            importProgress = ImportProgress(fraction: 0.4, message: "Reading \(filename)")
        }

        let metadata = await ChapterService.inspect(url: destination)
        let title = metadata.title ?? FileOrdering.displayTitle(from: filename)
        let markers = await ChapterService.parseChapters(files: [destination], bookTitle: title)
        if let artwork = metadata.artwork {
            ArtworkStore.writeEmbedded(artwork, bookID: stagingID)
        }
        ArtworkStore.copyFolderCover(from: url.deletingLastPathComponent(), bookID: stagingID)

        let file = BookFile(relativePath: filename, sortIndex: 0, duration: metadata.duration)
        try await commitStagedImport(
            stagingID: stagingID,
            title: title,
            author: metadata.author ?? "Unknown Author",
            narrator: metadata.narrator,
            sourceFilename: filename,
            duration: metadata.duration,
            files: [file],
            markers: markers,
            destinations: [destination],
            filenames: [filename]
        )
    }

    private func importCombined(_ urls: [URL]) async throws {
        let sorted = FileOrdering.combineSort(urls)
        if let blocked = sorted.first(where: { DRMGuard.isBlocked($0) }) {
            _ = blocked
            throw ImportError.drm
        }
        let stagingID = UUID()
        let directory = try BookStorage.ensureDirectory(for: stagingID)
        var files: [BookFile] = []
        var destinations: [URL] = []
        var filenames: [String] = []
        var totalDuration: TimeInterval = 0

        for (index, url) in sorted.enumerated() {
            await MainActor.run {
                importProgress = ImportProgress(
                    fraction: Double(index) / Double(max(sorted.count, 1)),
                    message: "Copying \(url.lastPathComponent)"
                )
            }
            let filename = BookStorage.uniqueFilename(
                "\(String(format: "%03d", index))-\(url.lastPathComponent)",
                in: directory
            )
            let destination = directory.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: url, to: destination)
            let metadata = await ChapterService.inspect(url: destination)
            let file = BookFile(relativePath: filename, sortIndex: index, duration: metadata.duration)
            files.append(file)
            destinations.append(destination)
            filenames.append(filename)
            totalDuration += metadata.duration
            if index == 0, let artwork = metadata.artwork {
                ArtworkStore.writeEmbedded(artwork, bookID: stagingID)
            }
        }
        ArtworkStore.copyFolderCover(from: sorted[0].deletingLastPathComponent(), bookID: stagingID)

        let firstMeta = await ChapterService.inspect(url: destinations[0])
        let title = firstMeta.title ?? FileOrdering.displayTitle(from: sorted[0].lastPathComponent)
        let markers = await ChapterService.parseChapters(files: destinations, bookTitle: title)

        try await commitStagedImport(
            stagingID: stagingID,
            title: title,
            author: firstMeta.author ?? "Unknown Author",
            narrator: firstMeta.narrator,
            sourceFilename: sorted.map(\.lastPathComponent).joined(separator: ", "),
            duration: totalDuration,
            files: files,
            markers: markers,
            destinations: destinations,
            filenames: filenames
        )
    }

    private func commitStagedImport(
        stagingID: UUID,
        title: String,
        author: String,
        narrator: String?,
        sourceFilename: String,
        duration: TimeInterval,
        files: [BookFile],
        markers: [ChapterMarker],
        destinations: [URL],
        filenames: [String]
    ) async throws {
        let destinationPaths = destinations.map(\.path)
        let fingerprint = await Task.detached {
            BookIdentityMath.makeFingerprint(
                title: title,
                author: author,
                duration: duration,
                fileURLs: destinationPaths.map { URL(fileURLWithPath: $0) },
                filenames: filenames
            )
        }.value

        let resolution = resolveIdentity(fingerprint, stagingID: stagingID)
        let bookID = resolution.bookID
        if bookID != stagingID {
            try BookStorage.moveDirectory(from: stagingID, to: bookID)
        }

        let book = Book(
            id: bookID,
            title: title,
            author: author,
            narrator: narrator,
            sourceFilename: sourceFilename,
            duration: duration,
            playbackRate: SettingsStore.shared.defaultSpeed
        )
        book.identityKey = fingerprint.identityKey
        // Reimport starts at 0 rather than guessing from the last session endPosition.
        book.position = 0
        if let finishedAt = resolution.finishedAt {
            book.isFinished = true
            book.finishedAt = finishedAt
        }
        for file in files {
            file.book = book
            book.files.append(file)
        }
        for (index, marker) in markers.enumerated() {
            let chapter = Chapter(
                title: marker.title,
                start: marker.start,
                duration: marker.duration,
                sortIndex: index,
                source: marker.source
            )
            chapter.book = book
            book.chapters.append(chapter)
        }
        if let reading = folders.first(where: { $0.name == "Currently Reading" }) {
            book.folder = reading
        }
        context.insert(book)
        upsertBookIdentity(
            bookID: bookID,
            fingerprint: fingerprint,
            title: title,
            author: author,
            narrator: narrator,
            finishedAt: book.finishedAt
        )
        save()
    }

    func resolveIdentity(_ fingerprint: BookFingerprint, stagingID: UUID) -> BookIdentityResolution {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let liveIDs = Set(books.map(\.id))
        let identities = ((try? context.fetch(FetchDescriptor<BookIdentity>())) ?? []).map {
            BookIdentityCandidate(
                bookID: $0.bookID,
                identityKey: $0.identityKey,
                title: $0.title,
                author: $0.author,
                duration: $0.duration,
                totalByteSize: $0.totalByteSize,
                sourceSignature: $0.sourceSignature,
                probeHash: $0.probeHash,
                lastSeenAt: $0.lastSeenAt,
                sessionCount: 0,
                finishedAt: $0.finishedAt
            )
        }
        let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
        let orphans = BookIdentityMath.orphanCandidates(
            sessions: sessions.map {
                OrphanSessionInput(
                    bookID: $0.bookID,
                    identityKey: $0.identityKey,
                    bookTitle: $0.bookTitle,
                    author: $0.author,
                    endedAt: $0.endedAt,
                    endReason: $0.endReason
                )
            },
            liveBookIDs: liveIDs
        )
        return BookIdentityMath.resolve(
            fingerprint: fingerprint,
            liveBookIDs: liveIDs,
            identities: identities,
            orphans: orphans,
            stagingID: stagingID
        )
    }

    private func persistIdentity(for book: Book) {
        let filenames = book.sortedFiles.map(\.relativePath)
        let urls = filenames.map { BookStorage.fileURL(bookID: book.id, relativePath: $0) }
        let totalSize = urls.reduce(Int64(0)) { $0 + BookIdentityMath.byteSize(of: $1) }
        let signature = BookIdentityMath.sourceSignature(filenames: filenames)
        let key = book.identityKey ?? BookIdentityMath.identityKey(
            title: book.title,
            author: book.author,
            duration: book.duration,
            totalByteSize: totalSize,
            fileCount: filenames.count,
            sourceSignature: signature
        )
        let fingerprint = BookFingerprint(
            identityKey: key,
            title: book.title,
            author: book.author,
            duration: book.duration,
            totalByteSize: totalSize,
            fileCount: filenames.count,
            sourceSignature: signature,
            probeHash: nil,
            filenames: filenames
        )
        upsertBookIdentity(
            bookID: book.id,
            fingerprint: fingerprint,
            title: book.title,
            author: book.author,
            narrator: book.narrator,
            finishedAt: book.finishedAt,
            preserveExistingKey: true
        )
    }

    private func upsertBookIdentity(
        bookID: UUID,
        fingerprint: BookFingerprint,
        title: String,
        author: String,
        narrator: String?,
        finishedAt: Date?,
        preserveExistingKey: Bool = false,
        now: Date = Date()
    ) {
        let existing = ((try? context.fetch(FetchDescriptor<BookIdentity>())) ?? []).first { $0.bookID == bookID }
        if let existing {
            if !preserveExistingKey {
                existing.identityKey = fingerprint.identityKey
                existing.totalByteSize = fingerprint.totalByteSize
                existing.sourceSignature = fingerprint.sourceSignature
                existing.probeHash = fingerprint.probeHash ?? existing.probeHash
            } else if existing.identityKey.isEmpty {
                existing.identityKey = fingerprint.identityKey
            }
            existing.title = title
            existing.author = author
            existing.narrator = narrator
            existing.duration = fingerprint.duration
            if !preserveExistingKey || existing.totalByteSize == 0 {
                existing.totalByteSize = fingerprint.totalByteSize
            }
            if !preserveExistingKey || existing.sourceSignature.isEmpty {
                existing.sourceSignature = fingerprint.sourceSignature
            }
            existing.lastSeenAt = now
            existing.finishedAt = finishedAt
        } else {
            context.insert(
                BookIdentity(
                    identityKey: fingerprint.identityKey,
                    bookID: bookID,
                    title: title,
                    author: author,
                    narrator: narrator,
                    duration: fingerprint.duration,
                    totalByteSize: fingerprint.totalByteSize,
                    sourceSignature: fingerprint.sourceSignature,
                    probeHash: fingerprint.probeHash,
                    lastSeenAt: now,
                    finishedAt: finishedAt
                )
            )
        }
    }

    private func seedDefaultFoldersIfNeeded() {
        if folders.isEmpty {
            context.insert(Folder(name: "Currently Reading", sortIndex: 0))
            context.insert(Folder(name: "Series", sortIndex: 1))
            save()
        }
    }
}

struct ImportProgress: Equatable {
    var fraction: Double
    var message: String
}

struct PendingCombine: Equatable {
    var urls: [URL]
    var blocked: [URL]
}

enum ImportError: LocalizedError {
    case drm
    case unreadable
    case emptyZip

    var errorDescription: String? {
        switch self {
        case .drm: return DRMGuard.rejectionMessage
        case .unreadable: return "Chapterline couldn’t read that file."
        case .emptyZip: return "That zip didn’t contain any playable audio."
        }
    }
}
