import AppIntents
import Foundation

struct ResumeCurrentBookIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Current Book"
    static var description = IntentDescription("Resume the audiobook you were listening to in Chapterline.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppRuntime.player?.resumeCurrent()
        return .result()
    }
}

struct ChapterlineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeCurrentBookIntent(),
            phrases: [
                "Resume my book in \(.applicationName)",
                "Resume current book in \(.applicationName)",
                "Continue listening in \(.applicationName)"
            ],
            shortTitle: "Resume book",
            systemImageName: "headphones"
        )
    }
}

struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if AppRuntime.player?.loadedBookID == nil {
            await AppRuntime.player?.resumeCurrent()
        } else {
            await AppRuntime.player?.toggle()
        }
        return .result()
    }
}
