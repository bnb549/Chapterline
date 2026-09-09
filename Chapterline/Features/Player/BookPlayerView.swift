import SwiftData
import SwiftUI
import UIKit

struct BookPlayerView: View {
    let bookID: UUID

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    @State private var showChapters = false
    @State private var showBookmarks = false
    @State private var showSleep = false
    @State private var showSpeed = false
    @State private var showEdit = false
    @State private var showBoost = false
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0

    var book: Book? { library.book(id: bookID) }

    var body: some View {
        Group {
            if let book {
                playerPage(book)
            } else {
                ContentUnavailableView("Book missing", systemImage: "book.closed")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showChapters) { if let book { ChapterListSheet(book: book) } }
        .sheet(isPresented: $showBookmarks) { if let book { BookmarkSheet(book: book) } }
        .sheet(isPresented: $showSleep) { SleepTimerSheet() }
        .sheet(isPresented: $showSpeed) { SpeedSheet() }
        .sheet(isPresented: $showEdit) { if let book { EditMetadataView(book: book) } }
        .sheet(isPresented: $showBoost) { BoostSheet() }
    }

    private func playerPage(_ book: Book) -> some View {
        let snap = player.snapshot
        let oled = settings.usesTrueBlack
        let tintOpacity: Double = {
            if oled { return 0.22 }
            return colorScheme == .dark ? 0.55 : 0.28
        }()
        return ZStack {
            LinearGradient(
                colors: [player.tint.opacity(tintOpacity), Theme.pageBackground(oled: oled)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                CoverView(book: book, cornerRadius: 16)
                    .frame(maxWidth: 280, maxHeight: 280)
                    .shadow(color: Theme.coverShadow, radius: 20, y: 10)
                    .padding(.top, 8)
                    .accessibilityLabel("Cover of \(book.title)")

                VStack(spacing: 4) {
                    Text(book.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                    Text(book.author)
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                    if let narrator = book.narrator, !narrator.isEmpty {
                        Text("Narrated by \(narrator)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 6) {
                    Text(snap.chapterTitle.isEmpty ? (book.currentChapter?.title ?? "Chapter 1") : snap.chapterTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if !settings.hideRemainingTime {
                        HStack {
                            Text("Chapter \(TimeMath.format(duration: snap.chapterRemaining))")
                            Spacer()
                            Text("Book \(TimeMath.format(duration: snap.remaining))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(voiceOverStatus(book: book, snap: snap))

                ChapterScrubber(
                    position: isScrubbing ? scrubPosition : snap.position,
                    duration: max(snap.duration, book.duration),
                    chapters: snap.chapters.isEmpty ? book.chapterMarkers : snap.chapters,
                    onScrub: { value in
                        isScrubbing = true
                        scrubPosition = value
                    },
                    onCommit: { value in
                        isScrubbing = false
                        Task { await player.seek(to: value) }
                    }
                )
                .padding(.horizontal, 20)

                TransportBar()
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                secondaryBar
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Chapters", systemImage: "list.bullet") { showChapters = true }
                    Button("Bookmarks", systemImage: "bookmark") { showBookmarks = true }
                    Button("Edit metadata", systemImage: "pencil") { showEdit = true }
                    Button("Reload chapters", systemImage: "arrow.clockwise") {
                        Task { await library.reloadChapters(for: book) }
                    }
                    Button("Jump to start", systemImage: "backward.end") {
                        Task { await player.jumpToStart() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
            }
        }
        .onChange(of: player.snapshot.rate) { _, rate in
            if let current = self.book, abs(current.playbackRate - rate) > 0.01 {
                current.playbackRate = rate
                library.save()
            }
        }
    }

    private var secondaryBar: some View {
        HStack(spacing: 10) {
            pill(player.snapshot.rate.formatted(.number.precision(.fractionLength(1))) + "×", systemImage: "gauge.with.dots.needle.33percent") {
                showSpeed = true
            }
            .accessibilityLabel("Speed \(String(format: "%.1f", player.snapshot.rate)) times")
            pill(sleepLabel, systemImage: "moon.zzz") { showSleep = true }
                .accessibilityLabel(sleepAccessibility)
            pill("Boost", systemImage: "waveform") { showBoost = true }
                .accessibilityLabel("Voice boost")
            pill("Marks", systemImage: "bookmark") { showBookmarks = true }
                .accessibilityLabel("Bookmarks")
        }
        .padding(.horizontal)
    }

    private var sleepLabel: String {
        if let remaining = player.snapshot.sleepRemaining {
            return TimeMath.format(duration: remaining)
        }
        return "Sleep"
    }

    private var sleepAccessibility: String {
        if let remaining = player.snapshot.sleepRemaining {
            return "Sleep timer, \(TimeMath.format(duration: remaining)) remaining"
        }
        return "Sleep timer"
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Theme.fill, in: Capsule())
                .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func voiceOverStatus(book: Book, snap: PlayerSnapshot) -> String {
        let remaining = settings.hideRemainingTime
            ? ""
            : ", \(TimeMath.formatRemaining(duration: snap.duration, position: snap.position, rate: snap.rate))"
        return "\(book.title), \(snap.chapterTitle), \(String(format: "%.1f", snap.rate)) times\(remaining)"
    }
}

struct TransportBar: View {
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 18) {
            control("Previous chapter", systemImage: "backward.end.fill") {
                Task { await player.previousChapter() }
            }
            control(skipBackLabel, systemImage: "gobackward") {
                Task { await player.skipBack() }
            }
            Button {
                Task { await player.toggle() }
            } label: {
                Image(systemName: player.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.playIcon)
                    .frame(width: 76, height: 76)
                    .background(Theme.playFill, in: Circle())
            }
            .accessibilityLabel(player.snapshot.isPlaying ? "Pause" : "Play")
            .accessibilityValue(voiceValue)

            control(skipForwardLabel, systemImage: "goforward") {
                Task { await player.skipForward() }
            }
            control("Next chapter", systemImage: "forward.end.fill") {
                Task { await player.nextChapter() }
            }
        }
        .padding(.vertical, 8)
    }

    private var skipBackLabel: String { "Skip back \(settings.skipBack.accessibilityLabel)" }
    private var skipForwardLabel: String { "Skip forward \(settings.skipForward.accessibilityLabel)" }

    private var voiceValue: String {
        let snap = player.snapshot
        return "\(snap.chapterTitle), \(TimeMath.formatRemaining(duration: snap.duration, position: snap.position, rate: snap.rate)), \(String(format: "%.1f", snap.rate)) times"
    }

    private func control(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .buttonStyle(.plain)
    }
}

struct ChapterScrubber: View {
    var position: TimeInterval
    var duration: TimeInterval
    var chapters: [ChapterMarker]
    var onScrub: (TimeInterval) -> Void
    var onCommit: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill).frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, width * CGFloat(TimeMath.progress(duration: duration, position: position))), height: 6)
                    ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                        if chapter.start > 0, duration > 0 {
                            Rectangle()
                                .fill(Theme.fillStrong)
                                .frame(width: 1.5, height: 10)
                                .offset(x: width * CGFloat(chapter.start / duration))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(1, max(0, value.location.x / width))
                            onScrub(fraction * duration)
                        }
                        .onEnded { value in
                            let fraction = min(1, max(0, value.location.x / width))
                            onCommit(fraction * duration)
                        }
                )
            }
            .frame(height: 44)
            HStack {
                Text(TimeMath.format(duration: position))
                Spacer()
                Text(TimeMath.format(duration: duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(TimeMath.format(duration: position))
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? 15 : -15
            onCommit(min(duration, max(0, position + delta)))
        }
    }
}
