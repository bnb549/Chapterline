import AVFoundation
import Foundation
import MediaPlayer

enum SleepMode: Equatable, Sendable {
    case until(Date)
    case endOfChapter
}

actor AudioPlayerService {
    nonisolated(unsafe) private let player = AVQueuePlayer()
    private var allItems: [AVPlayerItem] = []
    private var fileDurations: [TimeInterval] = []
    private var chapters: [ChapterMarker] = []
    private var loaded: LoadedBook?
    private var rate: Double = 1
    private var volume: Float = 1
    private var boostState = BoostState()
    private var intendedPlaying = false
    private var sleepMode: SleepMode?
    private var sleepFading = false
    private var lastPauseAt: Date?
    private var smartRewindEnabled = true
    private var sleepFadeSeconds: TimeInterval = 10
    private var sessionConfigured = false
    private var wasPlayingBeforeInterruption = false
    private var lastStopReason: SessionEndReason = .unknown

    func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            // Keep going; playback may still work on Simulator.
        }
        sessionConfigured = true
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func load(_ book: LoadedBook, smartRewind: Bool, fadeSeconds: TimeInterval, boost: Float) async {
        configureSessionIfNeeded()
        smartRewindEnabled = smartRewind
        sleepFadeSeconds = fadeSeconds
        boostState.gain = max(1, min(2, boost))

        // BookPlayerView.load runs from onAppear. Switching Library ↔ Settings
        // re-fires that without the user picking a different book — don't tear
        // down a live session.
        if loaded?.id == book.id, !allItems.isEmpty {
            var current = book
            current.rate = rate
            current.fileURLs = loaded?.fileURLs ?? book.fileURLs
            current.fileDurations = fileDurations
            loaded = current
            chapters = book.chapters
            return
        }

        cancelSleep()
        loaded = book
        fileDurations = book.fileDurations
        chapters = book.chapters
        rate = min(3, max(0.5, book.rate))
        lastPauseAt = nil
        intendedPlaying = false

        player.pause()
        player.removeAllItems()
        allItems = book.fileURLs.map { AVPlayerItem(url: $0) }
        for item in allItems {
            player.insert(item, after: nil)
            await VoiceBoost.attach(to: item, state: boostState)
        }
        player.volume = volume
        await seek(to: book.startPosition)
    }

    func snapshot() -> PlayerSnapshot {
        let position = currentAbsoluteTime()
        maybeHandleSleep(at: position)
        let chapter = TimeMath.chapter(at: position, in: chapters)
        let playing = intendedPlaying && player.rate != 0
        return PlayerSnapshot(
            bookID: loaded?.id,
            title: loaded?.title ?? "",
            author: loaded?.author ?? "",
            narrator: loaded?.narrator,
            chapterTitle: chapter?.title ?? loaded?.title ?? "",
            chapterIndex: TimeMath.chapterIndex(at: position, in: chapters),
            chapterStart: chapter?.start ?? 0,
            chapterDuration: chapter?.duration ?? (loaded.map { $0.fileDurations.reduce(0, +) } ?? 0),
            position: position,
            duration: fileDurations.reduce(0, +),
            rate: rate,
            isPlaying: playing,
            volume: volume,
            boost: boostState.gain,
            sleepEndsAt: sleepDeadline(at: position),
            sleepFading: sleepFading,
            chapters: chapters,
            fileDurations: fileDurations,
            stopReason: playing ? nil : lastStopReason
        )
    }

    func play(applyingSmartRewind: Bool = true) async {
        configureSessionIfNeeded()
        try? AVAudioSession.sharedInstance().setActive(true)
        if applyingSmartRewind, !intendedPlaying {
            let position = currentAbsoluteTime()
            let chapterStart = TimeMath.chapter(at: position, in: chapters)?.start ?? 0
            let rewound = SmartRewind.apply(
                position: position,
                lastPauseAt: lastPauseAt,
                chapterStart: chapterStart,
                enabled: smartRewindEnabled
            )
            if abs(rewound - position) > 0.2 {
                await seek(to: rewound)
            }
        }
        intendedPlaying = true
        lastPauseAt = nil
        player.rate = Float(rate)
        if player.rate == 0 {
            player.play()
            player.rate = Float(rate)
        }
    }

    func pause(reason: SessionEndReason = .pause) {
        intendedPlaying = false
        lastPauseAt = Date()
        lastStopReason = reason
        player.pause()
        sleepFading = false
        player.volume = volume
    }

    func isIntendedPlaying() -> Bool { intendedPlaying }

    func toggle() async {
        if intendedPlaying {
            pause()
        } else {
            await play()
        }
    }

    func seek(to absolute: TimeInterval) async {
        let total = fileDurations.reduce(0, +)
        guard total > 0, !allItems.isEmpty else { return }
        let clamped = min(max(0, absolute), total)
        let location = TimeMath.fileLocation(absoluteTime: clamped, fileDurations: fileDurations)
        rebuildQueue(from: location.index)
        let time = CMTime(seconds: location.localTime, preferredTimescale: 600)
        await player.currentItem?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if intendedPlaying {
            player.rate = Float(rate)
        }
    }

    func skip(interval: SkipInterval, forward: Bool) async {
        let position = currentAbsoluteTime()
        if interval.isChapter {
            if forward {
                if let start = TimeMath.nextChapterStart(at: position, in: chapters) {
                    await seek(to: start)
                }
            } else if let start = TimeMath.previousChapterStart(at: position, in: chapters) {
                await seek(to: start)
            }
            return
        }
        let delta = TimeInterval(interval.secondsValue ?? 15)
        let target = forward ? position + delta : position - delta
        await seek(to: target)
    }

    func nextChapter() async {
        await skip(interval: .chapter, forward: true)
    }

    func previousChapter() async {
        await skip(interval: .chapter, forward: false)
    }

    func jumpToStart() async {
        await seek(to: 0)
    }

    func setRate(_ newRate: Double) {
        rate = min(3, max(0.5, (newRate * 10).rounded() / 10))
        if intendedPlaying {
            player.rate = Float(rate)
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = min(1, max(0, newVolume))
        if !sleepFading {
            player.volume = volume
        }
    }

    func setBoost(_ gain: Float) {
        boostState.gain = min(2, max(1, gain))
    }

    func setSmartRewindEnabled(_ enabled: Bool) {
        smartRewindEnabled = enabled
    }

    func setSleepFadeSeconds(_ seconds: TimeInterval) {
        sleepFadeSeconds = max(1, seconds)
    }

    func startSleep(minutes: Double) {
        sleepFading = false
        player.volume = volume
        sleepMode = .until(Date().addingTimeInterval(minutes * 60))
    }

    func startSleepEndOfChapter() {
        sleepFading = false
        player.volume = volume
        sleepMode = .endOfChapter
    }

    func extendSleep(byMinutes minutes: Double = 15) {
        switch sleepMode {
        case .until(let date):
            sleepMode = .until(date.addingTimeInterval(minutes * 60))
        case .endOfChapter:
            sleepMode = .until(Date().addingTimeInterval(minutes * 60))
        case .none:
            sleepMode = .until(Date().addingTimeInterval(minutes * 60))
        }
        sleepFading = false
        player.volume = volume
    }

    func cancelSleep() {
        sleepMode = nil
        sleepFading = false
        player.volume = volume
    }

    func handleInterruptionBegan() {
        wasPlayingBeforeInterruption = intendedPlaying
        lastStopReason = .interruption
        player.pause()
    }

    func handleInterruptionEnded(shouldResume: Bool) async {
        if shouldResume && wasPlayingBeforeInterruption {
            await play()
        }
    }

    func handleRouteChange(shouldPause: Bool) {
        if shouldPause {
            pause(reason: .routeChange)
        }
    }

    func unload() {
        pause()
        cancelSleep()
        player.removeAllItems()
        allItems = []
        loaded = nil
        fileDurations = []
        chapters = []
    }

    private func rebuildQueue(from index: Int) {
        let current = player.currentItem
        let currentIndex = current.flatMap { item in allItems.firstIndex(where: { $0 === item }) }
        if currentIndex == index { return }
        let wasPlaying = intendedPlaying
        player.removeAllItems()
        let start = min(max(0, index), max(0, allItems.count - 1))
        for item in allItems[start...] {
            player.insert(item, after: nil)
        }
        if wasPlaying {
            player.rate = Float(rate)
        }
    }

    private func currentAbsoluteTime() -> TimeInterval {
        guard let current = player.currentItem else { return 0 }
        let local = current.currentTime().seconds
        let safeLocal = local.isFinite ? max(0, local) : 0
        let index = allItems.firstIndex(where: { $0 === current }) ?? 0
        return TimeMath.absoluteTime(fileIndex: index, localTime: safeLocal, fileDurations: fileDurations)
    }

    private func sleepDeadline(at position: TimeInterval) -> Date? {
        switch sleepMode {
        case .until(let date):
            return date
        case .endOfChapter:
            let remaining = TimeMath.chapter(at: position, in: chapters).map {
                TimeMath.remaining(duration: $0.end, position: position, rate: rate)
            } ?? 0
            return Date().addingTimeInterval(remaining)
        case .none:
            return nil
        }
    }

    private func maybeHandleSleep(at position: TimeInterval) {
        guard let deadline = sleepDeadline(at: position) else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            pause(reason: .sleepTimer)
            sleepMode = nil
            sleepFading = false
            player.volume = volume
            return
        }
        if remaining <= sleepFadeSeconds {
            sleepFading = true
            let fraction = Float(remaining / sleepFadeSeconds)
            player.volume = volume * max(0, fraction)
        } else if sleepFading {
            sleepFading = false
            player.volume = volume
        }
    }
}
