import Foundation
import SwiftUI

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    var skipBack: SkipInterval {
        didSet { defaults.set(skipBack.storageValue, forKey: Key.skipBack) }
    }
    var skipForward: SkipInterval {
        didSet { defaults.set(skipForward.storageValue, forKey: Key.skipForward) }
    }
    var defaultSpeed: Double {
        didSet { defaults.set(defaultSpeed, forKey: Key.defaultSpeed) }
    }
    var smartRewindEnabled: Bool {
        didSet { defaults.set(smartRewindEnabled, forKey: Key.smartRewind) }
    }
    var sleepFadeSeconds: Double {
        didSet { defaults.set(sleepFadeSeconds, forKey: Key.sleepFade) }
    }
    var boost: Double {
        didSet { defaults.set(boost, forKey: Key.boost) }
    }
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    var hideRemainingTime: Bool {
        didSet { defaults.set(hideRemainingTime, forKey: Key.hideRemaining) }
    }
    var carPlayOpenPlayerOnLaunch: Bool {
        didSet { defaults.set(carPlayOpenPlayerOnLaunch, forKey: Key.carPlayOpen) }
    }
    var libraryLayout: LibraryLayout {
        didSet { defaults.set(libraryLayout.rawValue, forKey: Key.layout) }
    }
    var librarySort: LibrarySort {
        didSet { defaults.set(librarySort.rawValue, forKey: Key.sort) }
    }
    var shakeToExtendSleep: Bool {
        didSet { defaults.set(shakeToExtendSleep, forKey: Key.shakeExtend) }
    }
    var trackListeningStats: Bool {
        didSet { defaults.set(trackListeningStats, forKey: Key.trackListeningStats) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skipBack = SkipInterval(storageValue: defaults.string(forKey: Key.skipBack) ?? "s-15")
        skipForward = SkipInterval(storageValue: defaults.string(forKey: Key.skipForward) ?? "s-30")
        let speed = defaults.object(forKey: Key.defaultSpeed) as? Double ?? 1.0
        defaultSpeed = min(3, max(0.5, speed))
        smartRewindEnabled = defaults.object(forKey: Key.smartRewind) as? Bool ?? true
        sleepFadeSeconds = defaults.object(forKey: Key.sleepFade) as? Double ?? 10
        boost = defaults.object(forKey: Key.boost) as? Double ?? 1.0
        let storedAppearance = defaults.string(forKey: Key.appearance) ?? "dark"
        let resolvedAppearance = storedAppearance == "dim" ? "dark" : storedAppearance
        appearance = AppearanceMode(rawValue: resolvedAppearance) ?? .dark
        if storedAppearance == "dim" {
            defaults.set(AppearanceMode.dark.rawValue, forKey: Key.appearance)
        }
        hideRemainingTime = defaults.bool(forKey: Key.hideRemaining)
        carPlayOpenPlayerOnLaunch = defaults.object(forKey: Key.carPlayOpen) as? Bool ?? true
        libraryLayout = LibraryLayout(rawValue: defaults.string(forKey: Key.layout) ?? "grid") ?? .grid
        librarySort = LibrarySort(rawValue: defaults.string(forKey: Key.sort) ?? "recent") ?? .recent
        shakeToExtendSleep = defaults.object(forKey: Key.shakeExtend) as? Bool ?? true
        trackListeningStats = defaults.object(forKey: Key.trackListeningStats) as? Bool ?? true
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        }
    }

    var usesTrueBlack: Bool { appearance.usesTrueBlack }

    private enum Key {
        static let skipBack = "settings.skipBack"
        static let skipForward = "settings.skipForward"
        static let defaultSpeed = "settings.defaultSpeed"
        static let smartRewind = "settings.smartRewind"
        static let sleepFade = "settings.sleepFade"
        static let boost = "settings.boost"
        static let appearance = "settings.appearance"
        static let hideRemaining = "settings.hideRemaining"
        static let carPlayOpen = "settings.carPlayOpen"
        static let layout = "settings.layout"
        static let sort = "settings.sort"
        static let shakeExtend = "settings.shakeExtend"
        static let trackListeningStats = "settings.trackListeningStats"
    }
}
