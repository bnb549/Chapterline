import Foundation

enum AppRuntime {
    static var library: LibraryStore!
    static var player: PlayerController!
    static var settings: SettingsStore!
}

extension Notification.Name {
    static let chapterlineInbox = Notification.Name("chapterline.inbox")
}

enum DarwinImport {
    private static var registered = false

    static func start() {
        guard !registered else { return }
        registered = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .chapterlineInbox, object: nil)
                }
            },
            AppGroup.darwinImport as CFString,
            nil,
            .deliverImmediately
        )
    }
}
