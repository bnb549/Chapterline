import Foundation
import SwiftUI
import UIKit
import WidgetKit

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// App Group key so the Home Screen widget can read the same accent.
    static let accentRGBAppGroupKey = "settings.accentRGB"

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
    /// Display P3 components for the app accent. Changing these updates tint and the widget.
    private(set) var accentRed: Double
    private(set) var accentGreen: Double
    private(set) var accentBlue: Double
    var hideRemainingTime: Bool {
        didSet { defaults.set(hideRemainingTime, forKey: Key.hideRemaining) }
    }
    var allowBookScrubbing: Bool {
        didSet { defaults.set(allowBookScrubbing, forKey: Key.allowBookScrubbing) }
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
        let fallback = AccentSwatch.default.components
        if let stored = defaults.array(forKey: Key.accentRGB) as? [Double], stored.count == 3 {
            accentRed = Self.clampedComponent(stored[0])
            accentGreen = Self.clampedComponent(stored[1])
            accentBlue = Self.clampedComponent(stored[2])
        } else {
            accentRed = fallback.red
            accentGreen = fallback.green
            accentBlue = fallback.blue
        }
        hideRemainingTime = defaults.bool(forKey: Key.hideRemaining)
        allowBookScrubbing = defaults.object(forKey: Key.allowBookScrubbing) as? Bool ?? true
        libraryLayout = LibraryLayout(rawValue: defaults.string(forKey: Key.layout) ?? "grid") ?? .grid
        librarySort = LibrarySort(rawValue: defaults.string(forKey: Key.sort) ?? "recent") ?? .recent
        shakeToExtendSleep = defaults.object(forKey: Key.shakeExtend) as? Bool ?? true
        trackListeningStats = defaults.object(forKey: Key.trackListeningStats) as? Bool ?? true
        syncAccentToAppGroup(reloadWidget: false)
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        }
    }

    var usesTrueBlack: Bool { appearance.usesTrueBlack }

    var accentColor: Color {
        Color(.displayP3, red: accentRed, green: accentGreen, blue: accentBlue, opacity: 1)
    }

    func applyAccent(_ swatch: AccentSwatch) {
        let c = swatch.components
        setAccentComponents(red: c.red, green: c.green, blue: c.blue)
    }

    func applyAccent(_ color: Color) {
        let c = Self.displayP3Components(from: color)
        setAccentComponents(red: c.red, green: c.green, blue: c.blue)
    }

    func matchesAccent(_ swatch: AccentSwatch) -> Bool {
        let c = swatch.components
        return abs(accentRed - c.red) < 0.02
            && abs(accentGreen - c.green) < 0.02
            && abs(accentBlue - c.blue) < 0.02
    }

    private func setAccentComponents(red: Double, green: Double, blue: Double) {
        let r = Self.clampedComponent(red)
        let g = Self.clampedComponent(green)
        let b = Self.clampedComponent(blue)
        guard accentRed != r || accentGreen != g || accentBlue != b else { return }
        accentRed = r
        accentGreen = g
        accentBlue = b
        defaults.set([r, g, b], forKey: Key.accentRGB)
        syncAccentToAppGroup(reloadWidget: true)
    }

    private func syncAccentToAppGroup(reloadWidget: Bool) {
        guard let suite = UserDefaults(suiteName: AppGroup.identifier) else { return }
        suite.set([accentRed, accentGreen, accentBlue], forKey: Self.accentRGBAppGroupKey)
        guard reloadWidget else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "ChapterlineWidget")
    }

    private static func clampedComponent(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func displayP3Components(from color: Color) -> (red: Double, green: Double, blue: Double) {
        let ui = UIColor(color)
        if let space = CGColorSpace(name: CGColorSpace.displayP3),
           let converted = ui.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
           let components = converted.components,
           components.count >= 3 {
            return (
                clampedComponent(Double(components[0])),
                clampedComponent(Double(components[1])),
                clampedComponent(Double(components[2]))
            )
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (clampedComponent(Double(r)), clampedComponent(Double(g)), clampedComponent(Double(b)))
    }

    private enum Key {
        static let skipBack = "settings.skipBack"
        static let skipForward = "settings.skipForward"
        static let defaultSpeed = "settings.defaultSpeed"
        static let smartRewind = "settings.smartRewind"
        static let sleepFade = "settings.sleepFade"
        static let boost = "settings.boost"
        static let appearance = "settings.appearance"
        static let accentRGB = "settings.accentRGB"
        static let hideRemaining = "settings.hideRemaining"
        static let allowBookScrubbing = "settings.allowBookScrubbing"
        static let layout = "settings.layout"
        static let sort = "settings.sort"
        static let shakeExtend = "settings.shakeExtend"
        static let trackListeningStats = "settings.trackListeningStats"
    }
}
