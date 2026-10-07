import SwiftUI
import UIKit

enum NowPlayingChrome: Sendable {
    nonisolated static func isListening(_ snapshot: PlayerSnapshot) -> Bool {
        snapshot.isPlaying && snapshot.bookID != nil
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

/// Compact listening bar. It reads the player snapshot and does not own an `AVPlayer`.
struct NowPlayingBar: View {
    var onOpen: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    cover
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now Playing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(player.snapshot.title)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(detailLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now playing, \(player.snapshot.title), \(detailLine)")
            .accessibilityHint("Opens the player")

            Button {
                Task { await player.pause() }
            } label: {
                Image(systemName: "pause.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause")
            .accessibilityHint("Pauses playback")
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

    private var detailLine: String {
        let snap = player.snapshot
        let finished = playingBook?.isFinished ?? false
        return NowPlayingChrome.detailLine(
            chapterTitle: snap.chapterTitle,
            hideRemainingTime: settings.hideRemainingTime,
            isFinished: finished,
            progress: snap.progress,
            duration: snap.duration,
            position: snap.position,
            rate: snap.rate
        )
    }

    private var playingBook: Book? {
        guard let id = player.snapshot.bookID else { return nil }
        return library.book(id: id)
    }

    private var cover: some View {
        Image(uiImage: coverImage)
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

    private var coverImage: UIImage {
        if let artwork = player.artwork { return artwork }
        if let book = playingBook { return ArtworkStore.image(for: book) }
        return ArtworkStore.monogram(title: player.snapshot.title, author: player.snapshot.author)
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
