import SwiftUI
import UIKit
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WidgetSnapshot: Codable {
    var title: String
    var author: String
    var chapterTitle: String
    var isPlaying: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: WidgetSnapshot(title: "Chapterline", author: "", chapterTitle: "Nothing playing", isPlaying: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = NowPlayingEntry(date: Date(), snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.benmonroe.free-player")?
            .appendingPathComponent("now-playing.json")
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(FileSnapshot.self, from: data) {
            return WidgetSnapshot(
                title: decoded.title.isEmpty ? "Chapterline" : decoded.title,
                author: decoded.author,
                chapterTitle: decoded.chapterTitle,
                isPlaying: decoded.isPlaying
            )
        }
        return WidgetSnapshot(title: "Chapterline", author: "", chapterTitle: "Open a book to begin", isPlaying: false)
    }

    private struct FileSnapshot: Codable {
        var title: String
        var author: String
        var chapterTitle: String
        var isPlaying: Bool
    }
}

struct ChapterlineWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.snapshot.title)
                .font(.headline)
                .lineLimit(2)
            Text(entry.snapshot.chapterTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            HStack {
                Text(entry.snapshot.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Link(destination: URL(string: "chapterline://toggle")!) {
                    Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.85), in: Circle())
                }
                .accessibilityLabel(entry.snapshot.isPlaying ? "Pause" : "Play")
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

struct ChapterlineWidget: Widget {
    let kind = "ChapterlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ChapterlineWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Cover, title, and play/pause for the current book.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ChapterlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChapterlineWidget()
    }
}
