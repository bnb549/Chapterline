import AVFoundation
import CoreMotion
import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class PlayerController {
    let engine = AudioPlayerService()
    var snapshot = PlayerSnapshot.empty
    var artwork: UIImage?
    var tint: Color = Color(red: 0.12, green: 0.1, blue: 0.08)
    var loadedBookID: UUID?

    var onPersist: ((UUID, TimeInterval, Double, Bool, Bool) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var lastPersistAt = Date.distantPast
    private var lastPersistedPosition: TimeInterval = -1
    private let motion = CMMotionManager()
    private var lastShakeAt = Date.distantPast
    var shakeToExtend = true

    func start() {
        guard pollTask == nil else { return }
        NowPlayingBridge.shared.install(controller: self)
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let snap = await self.engine.snapshot()
                self.snapshot = snap
                self.persistIfNeeded(snap)
                NowPlayingBridge.shared.publish(snap, artwork: self.artwork)
                self.writeWidgetSnapshot(snap)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        startShakeMonitor()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                await self?.handleInterruption(notification)
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                await self?.handleRouteChange(notification)
            }
        }
    }

    func load(book: Book) async {
        let files = book.sortedFiles
        let urls = files.map { BookStorage.fileURL(bookID: book.id, relativePath: $0.relativePath) }
        let loaded = LoadedBook(
            id: book.id,
            title: book.title,
            author: book.author,
            narrator: book.narrator,
            fileURLs: urls,
            fileDurations: files.map(\.duration),
            chapters: book.chapterMarkers,
            artworkData: ArtworkStore.data(for: book),
            rate: book.playbackRate,
            startPosition: book.isFinished ? 0 : book.position
        )
        let settings = SettingsStore.shared
        await engine.load(
            loaded,
            smartRewind: settings.smartRewindEnabled,
            fadeSeconds: settings.sleepFadeSeconds,
            boost: Float(settings.boost)
        )
        loadedBookID = book.id
        artwork = ArtworkStore.image(for: book)
        tint = ArtworkStore.averageColor(from: artwork ?? UIImage())
        snapshot = await engine.snapshot()
        NowPlayingBridge.shared.publish(snapshot, artwork: artwork)
    }

    func play() async { await engine.play() }
    func pause() async { await engine.pause() }
    func toggle() async { await engine.toggle() }
    func seek(to time: TimeInterval) async { await engine.seek(to: time) }
    func skipBack() async { await engine.skip(interval: SettingsStore.shared.skipBack, forward: false) }
    func skipForward() async { await engine.skip(interval: SettingsStore.shared.skipForward, forward: true) }
    func nextChapter() async { await engine.nextChapter() }
    func previousChapter() async { await engine.previousChapter() }
    func jumpToStart() async { await engine.jumpToStart() }
    func setRate(_ rate: Double) async { await engine.setRate(rate) }
    func setBoost(_ boost: Double) async { await engine.setBoost(Float(boost)) }
    func startSleep(minutes: Double) async { await engine.startSleep(minutes: minutes) }
    func startSleepEndOfChapter() async { await engine.startSleepEndOfChapter() }
    func cancelSleep() async { await engine.cancelSleep() }
    func extendSleep() async { await engine.extendSleep() }

    func resumeCurrent() async {
        if loadedBookID == nil, let book = AppRuntime.library?.continueListening {
            await load(book: book)
        }
        await play()
    }

    func persistNow() {
        persistIfNeeded(snapshot, force: true)
    }

    private func persistIfNeeded(_ snap: PlayerSnapshot, force: Bool = false) {
        guard let id = snap.bookID else { return }
        let due = Date().timeIntervalSince(lastPersistAt) >= 1 || force
        let moved = abs(snap.position - lastPersistedPosition) >= 0.5
        guard due && (moved || force || !snap.isPlaying) else { return }
        lastPersistAt = Date()
        lastPersistedPosition = snap.position
        let finished = snap.duration > 0 && snap.position >= snap.duration - 1
        onPersist?(id, snap.position, snap.rate, snap.isPlaying, finished)
    }

    private func writeWidgetSnapshot(_ snap: PlayerSnapshot) {
        guard let url = AppGroup.snapshotURL else { return }
        let payload = NowPlayingSnapshot(
            bookID: snap.bookID,
            title: snap.title,
            author: snap.author,
            chapterTitle: snap.chapterTitle,
            isPlaying: snap.isPlaying,
            position: snap.position,
            duration: snap.duration,
            rate: snap.rate,
            coverRelativePath: snap.bookID.map { BookStorage.embeddedCoverName + ":" + $0.uuidString }
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func startShakeMonitor() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.15
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, self.shakeToExtend, let data else { return }
            let magnitude = abs(data.acceleration.x) + abs(data.acceleration.y) + abs(data.acceleration.z)
            guard magnitude > 2.8, Date().timeIntervalSince(self.lastShakeAt) > 1.5 else { return }
            self.lastShakeAt = Date()
            guard self.snapshot.sleepEndsAt != nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await self.extendSleep() }
        }
    }

    private func handleInterruption(_ notification: Notification) async {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            await engine.handleInterruptionBegan()
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            await engine.handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) async {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            await engine.handleRouteChange(shouldPause: true)
        }
    }
}
