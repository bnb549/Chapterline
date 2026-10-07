import SwiftUI
import UIKit

enum NowPlayingChrome: Sendable {
    struct Content: Equatable, Sendable {
        var bookID: UUID
        var isPlaying: Bool
    }

    nonisolated static func isListening(_ snapshot: PlayerSnapshot) -> Bool {
        snapshot.isPlaying && snapshot.bookID != nil
    }

    /// Playing session wins. A paused, unfinished loaded book is the resume target.
    /// A finished or missing loaded book falls through to Continue Listening.
    /// `loadedBookIsFinished == nil` means that book is not in the library.
    nonisolated static func barContent(
        snapshotBookID: UUID?,
        isPlaying: Bool,
        loadedBookIsFinished: Bool?,
        continueBookID: UUID?
    ) -> Content? {
        if isPlaying, let id = snapshotBookID {
            return Content(bookID: id, isPlaying: true)
        }
        if let id = snapshotBookID, loadedBookIsFinished == false {
            return Content(bookID: id, isPlaying: false)
        }
        if let id = continueBookID {
            return Content(bookID: id, isPlaying: false)
        }
        return nil
    }

    /// Chapter title when the snapshot has one. Otherwise the same finished /
    /// percent / remaining rules as `RemainingLabel`.
    nonisolated static func detailLine(
        chapterTitle: String,
        hideRemainingTime: Bool,
        isFinished: Bool,
        progress: Double,
        duration: TimeInterval,
        position: TimeInterval,
        rate: Double
    ) -> String {
        let chapter = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapter.isEmpty { return chapter }
        if hideRemainingTime {
            return isFinished ? "Finished" : "\(Int((progress * 100).rounded()))%"
        }
        if isFinished { return "Finished" }
        return TimeMath.formatRemaining(duration: duration, position: position, rate: rate)
    }
}

/// Compact listening and resume bar. It reads the player snapshot and library and does not own an `AVPlayer`.
struct NowPlayingBar: View {
    var onOpen: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if let content, let book = library.book(id: content.bookID) {
            bar(content: content, book: book)
        }
    }

    private func bar(content: NowPlayingChrome.Content, book: Book) -> some View {
        let title = displayTitle(for: book)
        let detail = detailLine(for: book)
        return HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    cover(for: book)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.isPlaying ? "Now Playing" : "Continue Listening")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(openLabel(isPlaying: content.isPlaying, title: title, detail: detail))
            .accessibilityHint("Opens the player")

            Button {
                Task { await transport(content: content, book: book) }
            } label: {
                Image(systemName: content.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(content.isPlaying ? "Pause" : "Play")
            .accessibilityHint(content.isPlaying ? "Pauses playback" : "Resumes playback")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            Theme.chromeBackground(oled: settings.usesTrueBlack),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var content: NowPlayingChrome.Content? {
        let snapshot = player.snapshot
        let finished: Bool? = {
            guard let id = snapshot.bookID else { return nil }
            return library.book(id: id)?.isFinished
        }()
        return NowPlayingChrome.barContent(
            snapshotBookID: snapshot.bookID,
            isPlaying: snapshot.isPlaying,
            loadedBookIsFinished: finished,
            continueBookID: library.continueListening?.id
        )
    }

    private func transport(content: NowPlayingChrome.Content, book: Book) async {
        if content.isPlaying {
            await player.pause()
        } else {
            await player.resume(book)
        }
    }

    private func openLabel(isPlaying: Bool, title: String, detail: String) -> String {
        let caption = isPlaying ? "Now playing" : "Continue listening"
        return "\(caption), \(title), \(detail)"
    }

    private func displayTitle(for book: Book) -> String {
        if usesLiveSnapshot(for: book) {
            return player.snapshot.title
        }
        return book.title
    }

    private func detailLine(for book: Book) -> String {
        if usesLiveSnapshot(for: book) {
            let snap = player.snapshot
            return NowPlayingChrome.detailLine(
                chapterTitle: snap.chapterTitle,
                hideRemainingTime: settings.hideRemainingTime,
                isFinished: book.isFinished,
                progress: snap.progress,
                duration: snap.duration,
                position: snap.position,
                rate: snap.rate
            )
        }
        return NowPlayingChrome.detailLine(
            chapterTitle: book.currentChapter?.title ?? "",
            hideRemainingTime: settings.hideRemainingTime,
            isFinished: book.isFinished,
            progress: book.progress,
            duration: book.duration,
            position: book.position,
            rate: book.playbackRate
        )
    }

    private func usesLiveSnapshot(for book: Book) -> Bool {
        player.snapshot.bookID == book.id
    }

    private func cover(for book: Book) -> some View {
        Image(uiImage: coverImage(for: book))
            .resizable()
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private func coverImage(for book: Book) -> UIImage {
        if usesLiveSnapshot(for: book), let artwork = player.artwork {
            return artwork
        }
        return ArtworkStore.image(for: book)
    }
}

/// Page-colored strip so the rounded bar does not touch the screen edges
/// and an OLED page stays black around the chrome.
struct NowPlayingBarInset: View {
    var onOpen: () -> Void
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NowPlayingBar(onOpen: onOpen)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: NowPlayingBarHeightKey.self, value: proxy.size.height)
                }
            }
    }
}

struct NowPlayingBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NowPlayingClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height of the docked Now Playing bar, so scroll views can clear it.
    var nowPlayingClearance: CGFloat {
        get { self[NowPlayingClearanceKey.self] }
        set { self[NowPlayingClearanceKey.self] = newValue }
    }
}

extension View {
    /// Places the bar in the bottom safe area of a tab root, above the tab bar.
    func nowPlayingBar(visible: Bool, onOpen: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if visible {
                NowPlayingBarInset(onOpen: onOpen)
            }
        }
    }
}

/// Full-screen cover of the existing player. Not a second player route.
struct NowPlayingPlayerCover: View {
    let bookID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            BookPlayerView(bookID: bookID)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close player")
                    }
                }
        }
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}
