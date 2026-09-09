import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Color.accentColor)
        .preferredColorScheme(settings.preferredColorScheme)
        .toolbarBackground(settings.usesTrueBlack ? Color.black : Color.clear, for: .tabBar)
        .toolbarBackground(settings.usesTrueBlack ? .visible : .automatic, for: .tabBar)
        .onAppear {
            player.shakeToExtend = settings.shakeToExtendSleep
            player.start()
            player.onPersist = { id, position, rate, isPlaying, finished in
                library.updatePlayback(bookID: id, position: position, rate: rate, isPlaying: isPlaying, finished: finished)
            }
            Task { await library.drainShareInbox() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chapterlineInbox)) { _ in
            Task { await library.drainShareInbox() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                player.persistNow()
            }
            if phase == .active {
                Task { await library.drainShareInbox() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            player.persistNow()
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }

    private func handleOpenURL(_ url: URL) {
        if url.scheme == "chapterline" {
            Task {
                switch url.host {
                case "toggle":
                    await player.toggle()
                case "resume":
                    await player.resumeCurrent()
                default:
                    await player.resumeCurrent()
                }
            }
            return
        }
        Task { await library.handleIncomingURLs([url]) }
    }
}
