import Foundation

enum SkipInterval: Codable, Equatable, Hashable, CaseIterable {
    case seconds(Int)
    case chapter

    static let allCases: [SkipInterval] = [
        .seconds(15), .seconds(30), .seconds(45), .seconds(60), .chapter
    ]

    var secondsValue: Int? {
        if case .seconds(let value) = self { return value }
        return nil
    }

    var isChapter: Bool {
        if case .chapter = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .seconds(let value): return "\(value)s"
        case .chapter: return "Chapter"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .seconds(let value): return "\(value) seconds"
        case .chapter: return "Chapter"
        }
    }

    var storageValue: String {
        switch self {
        case .seconds(let value): return "s-\(value)"
        case .chapter: return "chapter"
        }
    }

    init(storageValue: String) {
        if storageValue == "chapter" {
            self = .chapter
        } else if storageValue.hasPrefix("s-"), let value = Int(storageValue.dropFirst(2)) {
            self = .seconds(value)
        } else {
            self = .seconds(15)
        }
    }
}

enum LibraryLayout: String, CaseIterable, Codable {
    case grid
    case list
}

enum LibrarySort: String, CaseIterable, Codable {
    case recent
    case author
    case title
    case progress

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .author: return "Author"
        case .title: return "Title"
        case .progress: return "Progress"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable {
    case system
    case light
    case dark
    case oled

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .oled: return "OLED"
        }
    }

    var usesTrueBlack: Bool { self == .oled }
}

/// Curated accent swatches. Components are Display P3 so they match the asset catalog red.
enum AccentSwatch: String, CaseIterable, Identifiable {
    case chapterline
    case orange
    case yellow
    case green
    case mint
    case teal
    case blue
    case indigo
    case purple
    case pink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chapterline: return "Chapterline red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        }
    }

    /// Display P3 red / green / blue in 0…1.
    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .chapterline: return (1, 0, 0.009)
        case .orange: return (1, 0.48, 0.08)
        case .yellow: return (0.98, 0.78, 0.1)
        case .green: return (0.22, 0.78, 0.35)
        case .mint: return (0.15, 0.82, 0.7)
        case .teal: return (0.12, 0.7, 0.78)
        case .blue: return (0.2, 0.52, 1)
        case .indigo: return (0.42, 0.36, 0.95)
        case .purple: return (0.72, 0.32, 0.95)
        case .pink: return (1, 0.28, 0.55)
        }
    }

    static let `default` = AccentSwatch.chapterline
}

enum ChapterSource: String, Codable {
    case embedded
    case file
    case synthetic
}
