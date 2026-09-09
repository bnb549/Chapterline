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

enum ChapterSource: String, Codable {
    case embedded
    case file
    case synthetic
}
