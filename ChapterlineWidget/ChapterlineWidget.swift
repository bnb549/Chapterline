import SwiftUI
import UIKit
import WidgetKit

private enum WidgetFiles {
    static let appGroup = "group.com.benmonroe.ChapterLine"
    static let snapshotName = "now-playing.json"
    static let coverName = "cover.jpg"
    static let toggleURL = URL(string: "chapterline://toggle")!
}

private enum WidgetPalette {
    /// Matches Settings → Accent color via the App Group. Falls back to Chapterline red.
    static var accent: Color {
        let key = "settings.accentRGB"
        if let values = UserDefaults(suiteName: WidgetFiles.appGroup)?.array(forKey: key) as? [Double],
           values.count == 3 {
            return Color(
                .displayP3,
                red: min(1, max(0, values[0])),
                green: min(1, max(0, values[1])),
                blue: min(1, max(0, values[2])),
                opacity: 1
            )
        }
        return Color(.displayP3, red: 1, green: 0, blue: 0.009, opacity: 1)
    }

    static func initials(from title: String) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "CL" : letters.joined()
    }

    static func monogram(title: String, author: String) -> (background: Color, accent: Color) {
        var hash: UInt64 = 5381
        for byte in (title + author).utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        return (
            Color(hue: hue, saturation: 0.45, brightness: 0.32),
            Color(hue: hue, saturation: 0.55, brightness: 0.62)
        )
    }
}

struct WidgetSnapshot: Equatable, Sendable {
    var title: String
    var author: String
    var chapterTitle: String
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var rate: Double
    var hasBook: Bool
    var coverFilename: String?

    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    var showsProgress: Bool {
        hasBook && duration > 0 && duration.isFinite && position.isFinite
    }

    var progress: Double {
        guard showsProgress else { return 0 }
        return min(1, max(0, position / duration))
    }

    var remainingText: String {
        let safeRate = rate > 0 && rate.isFinite ? rate : 1
        let remaining = max(0, duration - position) / safeRate
        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        if minutes > 0 { return "\(minutes)m left" }
        return "\(total)s left"
    }

    static let gallery = WidgetSnapshot(
        title: "The Raven",
        author: "Edgar Allan Poe",
        chapterTitle: "Once upon a midnight dreary",
        isPlaying: true,
        position: 86,
        duration: 240,
        rate: 1,
        hasBook: true,
        coverFilename: nil
    )

    static let empty = WidgetSnapshot(
        title: "",
        author: "",
        chapterTitle: "",
        isPlaying: false,
        position: 0,
        duration: 0,
        rate: 1,
        hasBook: false,
        coverFilename: nil
    )
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let coverJPEG: Data?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .gallery, coverJPEG: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        if context.isPreview {
            completion(NowPlayingEntry(date: Date(), snapshot: .gallery, coverJPEG: nil))
            return
        }
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
    }

    private func loadEntry() -> NowPlayingEntry {
        let snapshot = loadSnapshot()
        let cover = snapshot.coverFilename == WidgetFiles.coverName ? loadCoverJPEG() : nil
        return NowPlayingEntry(date: Date(), snapshot: snapshot, coverJPEG: cover)
    }

    private func loadSnapshot() -> WidgetSnapshot {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetFiles.appGroup)?
            .appendingPathComponent(WidgetFiles.snapshotName),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FileSnapshot.self, from: data),
              decoded.bookID != nil else {
            return .empty
        }
        let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = decoded.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapter = decoded.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidgetSnapshot(
            title: title,
            author: author,
            chapterTitle: chapter,
            isPlaying: decoded.isPlaying,
            position: decoded.position ?? 0,
            duration: decoded.duration ?? 0,
            rate: decoded.rate ?? 1,
            hasBook: true,
            coverFilename: decoded.coverRelativePath
        )
    }

    private func loadCoverJPEG() -> Data? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetFiles.appGroup)?
            .appendingPathComponent(WidgetFiles.coverName),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              data.count < 750_000 else {
            return nil
        }
        return data
    }

    private struct FileSnapshot: Codable {
        var bookID: UUID?
        var title: String
        var author: String
        var chapterTitle: String
        var isPlaying: Bool
        var position: TimeInterval?
        var duration: TimeInterval?
        var rate: Double?
        var coverRelativePath: String?
    }
}

struct ChapterlineWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NowPlayingEntry

    var body: some View {
        Group {
            if entry.snapshot.hasBook {
                if family == .systemMedium {
                    MediumNowPlaying(entry: entry)
                } else {
                    SmallNowPlaying(entry: entry)
                }
            } else {
                EmptyNowPlaying(family: family)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

private struct MediumNowPlaying: View {
    var entry: NowPlayingEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverArt(jpeg: entry.coverJPEG, title: entry.snapshot.displayTitle, author: entry.snapshot.author)
                .frame(width: 108, height: 108)
            ViewThatFits(in: .vertical) {
                MetadataStack(snapshot: entry.snapshot, showsAuthor: true, titleLines: 2)
                MetadataStack(snapshot: entry.snapshot, showsAuthor: false, titleLines: 2)
                MetadataStack(snapshot: entry.snapshot, showsAuthor: false, titleLines: 1)
            }
            PlayToggle(isPlaying: entry.snapshot.isPlaying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SmallNowPlaying: View {
    var entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverHero(entry: entry)
            ProgressBlock(snapshot: entry.snapshot, showsTime: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CoverHero: View {
    var entry: NowPlayingEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArt(
                jpeg: entry.coverJPEG,
                title: entry.snapshot.displayTitle,
                author: entry.snapshot.author,
                fills: true
            )
            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.snapshot.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !entry.snapshot.chapterTitle.isEmpty {
                    Text(entry.snapshot.chapterTitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 64)
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MetadataStack: View {
    var snapshot: WidgetSnapshot
    var showsAuthor: Bool
    var titleLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.8)
            if !snapshot.chapterTitle.isEmpty {
                Text(snapshot.chapterTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if showsAuthor, !snapshot.author.isEmpty {
                Text(snapshot.author)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if snapshot.showsProgress {
                ThinProgress(value: snapshot.progress)
                    .padding(.top, 4)
                Text(snapshot.remainingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressBlock: View {
    var snapshot: WidgetSnapshot
    var showsTime: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.showsProgress {
                ThinProgress(value: snapshot.progress)
            }
            HStack(alignment: .center, spacing: 8) {
                if showsTime, snapshot.showsProgress {
                    Text(snapshot.remainingText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                PlayToggle(isPlaying: snapshot.isPlaying)
            }
        }
    }
}

private struct EmptyNowPlaying: View {
    var family: WidgetFamily

    var body: some View {
        if family == .systemMedium {
            HStack(alignment: .center, spacing: 12) {
                EmptyMark()
                    .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chapterline")
                        .font(.headline)
                    Text("Open a book to begin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PlayToggle(isPlaying: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    EmptyMark()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chapterline")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Open a book to begin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    PlayToggle(isPlaying: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct EmptyMark: View {
    var body: some View {
        ZStack {
            WidgetPalette.accent.opacity(0.16)
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(WidgetPalette.accent)
        }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(WidgetPalette.accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct CoverArt: View {
    var jpeg: Data?
    var title: String
    var author: String
    var fills: Bool = false

    var body: some View {
        ZStack {
            if let jpeg, let image = UIImage(data: jpeg) {
                Color.primary.opacity(0.06)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: fills ? .fill : .fit)
                    }
                    .clipped()
            } else {
                MonogramCover(title: title, author: author)
            }
        }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct MonogramCover: View {
    var title: String
    var author: String

    var body: some View {
        let colors = WidgetPalette.monogram(title: title, author: author)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                colors.background
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    colors.accent.frame(height: side * 0.28)
                }
                Text(WidgetPalette.initials(from: title))
                    .font(.system(size: max(12, side * 0.32), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

private struct ThinProgress: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                Capsule()
                    .fill(WidgetPalette.accent)
                    .frame(width: max(0, width))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, value)) * 100).rounded())) percent")
    }
}

private struct PlayToggle: View {
    var isPlaying: Bool

    var body: some View {
        Link(destination: WidgetFiles.toggleURL) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .offset(x: isPlaying ? 0 : 1)
                .frame(width: 44, height: 44)
                .background(WidgetPalette.accent, in: Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint("Toggles playback")
    }
}

struct ChapterlineWidget: Widget {
    let kind = "ChapterlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ChapterlineWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Cover, progress, title, chapter, and play/pause for the current book.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct ChapterlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChapterlineWidget()
    }
}

#Preview(as: .systemSmall) {
    ChapterlineWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: .gallery, coverJPEG: nil)
    NowPlayingEntry(date: .now, snapshot: .empty, coverJPEG: nil)
}

#Preview(as: .systemMedium) {
    ChapterlineWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: .gallery, coverJPEG: nil)
    NowPlayingEntry(date: .now, snapshot: .empty, coverJPEG: nil)
}
