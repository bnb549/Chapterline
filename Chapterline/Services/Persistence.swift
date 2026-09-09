import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        Book.self,
        BookFile.self,
        Chapter.self,
        Bookmark.self,
        Folder.self,
        ListeningSession.self
    ])

    static let container: ModelContainer = {
        do {
            try BookStorage.ensureLibraryFolders()
            let configuration = ModelConfiguration(
                "Chapterline",
                schema: schema,
                url: BookStorage.storeURL
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
