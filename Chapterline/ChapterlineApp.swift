import SwiftData
import SwiftUI

@main
struct ChapterlineApp: App {
    @State private var settings = SettingsStore.shared
    @State private var player: PlayerController
    @State private var library: LibraryStore

    init() {
        let container = Persistence.container
        let store = LibraryStore(container: container)
        let player = PlayerController()
        _library = State(initialValue: store)
        _player = State(initialValue: player)
        AppRuntime.settings = SettingsStore.shared
        AppRuntime.library = store
        AppRuntime.player = player
        DarwinImport.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(library)
                .modelContainer(library.container)
                .onAppear {
                    AppRuntime.player = player
                    AppRuntime.library = library
                    AppRuntime.settings = settings
                }
        }
    }
}
