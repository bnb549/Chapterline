import SwiftData
import SwiftUI

@main
struct ChapterlineApp: App {
    @State private var settings = SettingsStore.shared
    @State private var player: PlayerController
    @State private var library: LibraryStore
    @State private var stats: ListeningStatsStore

    init() {
        let container = Persistence.container
        let store = LibraryStore(container: container)
        let stats = ListeningStatsStore(container: container, settings: SettingsStore.shared)
        let player = PlayerController()
        player.stats = stats
        _library = State(initialValue: store)
        _player = State(initialValue: player)
        _stats = State(initialValue: stats)
        AppRuntime.settings = SettingsStore.shared
        AppRuntime.library = store
        AppRuntime.player = player
        AppRuntime.stats = stats
        DarwinImport.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(library)
                .environment(stats)
                .modelContainer(library.container)
                .onAppear {
                    AppRuntime.player = player
                    AppRuntime.library = library
                    AppRuntime.settings = settings
                    AppRuntime.stats = stats
                    player.stats = stats
                }
        }
    }
}
