import AVFoundation
import CoreMotion
import Foundation
import Observation
import SwiftUI
import UIKit
import WidgetKit

@Observable
@MainActor
final class PlayerController {
    let engine = AudioPlayerService()
    var snapshot = PlayerSnapshot.empty
    var artwork: UIImage?
    var tint: Color = Color(red: 0.12, green: 0.1, blue: 0.08)
    var loadedBookID: UUID?

    var onPersist: ((UUID, TimeInterval, Double, Bool, Bool) -> Void)?
    var stats: ListeningStatsStore?

    private var pollTask: Task<Void, Never>?
    private var lastPersistAt = Date.distantPast
    private var lastPersistedPosition: TimeInterval = -1
    private let motion = CMMotionManager()
    private var lastShakeAt = Date.distantPast
    var shakeToExtend = true

    private var widgetCoverBookID: UUID?
    private var widgetCoverImageID: ObjectIdentifier?
    private var widgetCoverFailed = false
    private var didClearWidgetCover = false
    private var widgetReloadKey: String?
    private static let widgetCoverFilename = "cover.jpg"

    func start() {
        guard pollTask == nil else { return }
        NowPlayingBridge.shared.install(controller: self)
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let snap = await self.engine.snapshot()
                self.snapshot = snap
                self.persistIfNeeded(snap)
                self.stats?.ingest(snap)
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
        if let currentID = snapshot.bookID, currentID != book.id {
            stats?.closeOpenSession(reason: .skipAway, from: snapshot)
        }
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
        stats?.ingest(snapshot)
        NowPlayingBridge.shared.publish(snapshot, artwork: artwork)
        scheduleStaleChapterRescan(for: book.id)
    }

    /// Player UI hook. Skip `engine.load` when this book is already playing so the
    /// live session is not rebuilt, seeked, or restarted. A paused book still loads.
    func loadIfNeeded(book: Book) async {
        if loadedBookID == book.id, snapshot.isPlaying {
            return
        }
        await load(book: book)
    }

    /// Push a chapter reload into a book that is already loaded, without seeking.
    func refreshLoadedChapters(bookID: UUID) async {
        guard loadedBookID == bookID, let book = AppRuntime.library?.book(id: bookID) else { return }
        await load(book: book)
    }

    private func scheduleStaleChapterRescan(for bookID: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rescanStaleChaptersIfNeeded(bookID: bookID)
        }
    }

    private func rescanStaleChaptersIfNeeded(bookID: UUID) async {
        guard let library = AppRuntime.library, let book = library.book(id: bookID) else { return }
        let position = book.position
        let finished = book.isFinished
        let finishedAt = book.finishedAt
        guard let count = await library.rescanStaleSingleChapterBookIfNeeded(book), count > 1 else { return }
        guard loadedBookID == bookID, let updated = library.book(id: bookID) else { return }
        if updated.position != position || updated.isFinished != finished || updated.finishedAt != finishedAt {
            updated.position = position
            updated.isFinished = finished
            updated.finishedAt = finishedAt
            library.save()
        }
        await load(book: updated)
    }

    func play() async {
        await engine.play()
        await publishImmediate()
    }
    func pause() async {
        await engine.pause()
        await publishImmediate(forcePersist: true)
    }
    func toggle() async {
        await engine.toggle()
        await publishImmediate(forcePersist: true)
    }
    func seek(to time: TimeInterval) async { await engine.seek(to: time) }
    func skipBack() async { await engine.skip(interval: SettingsStore.shared.skipBack, forward: false) }
    func skipForward() async { await engine.skip(interval: SettingsStore.shared.skipForward, forward: true) }
    func nextChapter() async { await engine.nextChapter() }
    func previousChapter() async { await engine.previousChapter() }
    func jumpToStart() async { await engine.jumpToStart() }
    func setRate(_ rate: Double) async {
        await engine.setRate(rate)
        await publishImmediate()
    }
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

    /// Resume one book from the Now Playing bar. Reloads only when it is not already loaded,
    /// so a paused session is not seeked back to the stored position.
    func resume(_ book: Book) async {
        if loadedBookID != book.id {
            await load(book: book)
        }
        await play()
    }

    func persistNow() {
        persistIfNeeded(snapshot, force: true)
    }

    func closeStatsForTerminate() {
        persistIfNeeded(snapshot, force: true)
        stats?.closeOpenSession(reason: .background, from: snapshot)
    }

    private func publishImmediate(forcePersist: Bool = false) async {
        let snap = await engine.snapshot()
        snapshot = snap
        persistIfNeeded(snap, force: forcePersist)
        stats?.ingest(snap)
        NowPlayingBridge.shared.publish(snap, artwork: artwork)
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
        // `engine.load` can publish the incoming book before this controller stores
        // its artwork. Wait until the ids match so the shared cover belongs to that book.
        guard snap.bookID == loadedBookID, let url = AppGroup.snapshotURL else { return }
        let hasCover = syncWidgetCover(for: snap)
        let payload = NowPlayingSnapshot(
            bookID: snap.bookID,
            title: snap.title,
            author: snap.author,
            chapterTitle: snap.chapterTitle,
            isPlaying: snap.isPlaying,
            position: snap.position,
            duration: snap.duration,
            rate: snap.rate,
            coverRelativePath: hasCover ? Self.widgetCoverFilename : nil
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
        reloadWidgetTimelineIfNeeded(snap, hasCover: hasCover)
    }

    /// Downsamples the loaded artwork into the App Group once per book. Removes it when nothing is loaded.
    private func syncWidgetCover(for snap: PlayerSnapshot) -> Bool {
        guard let coverURL = AppGroup.containerURL?.appendingPathComponent(Self.widgetCoverFilename) else {
            return false
        }
        guard let bookID = snap.bookID, let artwork else {
            clearWidgetCover(at: coverURL)
            return false
        }
        didClearWidgetCover = false
        let imageID = ObjectIdentifier(artwork)
        if widgetCoverBookID == bookID, widgetCoverImageID == imageID {
            return !widgetCoverFailed
        }
        guard let data = Self.widgetThumbnailJPEG(from: artwork) else {
            widgetCoverBookID = bookID
            widgetCoverImageID = imageID
            widgetCoverFailed = true
            try? FileManager.default.removeItem(at: coverURL)
            return false
        }
        do {
            try data.write(to: coverURL, options: .atomic)
            widgetCoverBookID = bookID
            widgetCoverImageID = imageID
            widgetCoverFailed = false
            return true
        } catch {
            widgetCoverBookID = bookID
            widgetCoverImageID = imageID
            widgetCoverFailed = true
            try? FileManager.default.removeItem(at: coverURL)
            return false
        }
    }

    private func clearWidgetCover(at url: URL) {
        guard widgetCoverBookID != nil || widgetCoverImageID != nil || !didClearWidgetCover else { return }
        widgetCoverBookID = nil
        widgetCoverImageID = nil
        widgetCoverFailed = false
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        didClearWidgetCover = true
    }

    private func reloadWidgetTimelineIfNeeded(_ snap: PlayerSnapshot, hasCover: Bool) {
        let key = [
            snap.bookID?.uuidString ?? "-",
            snap.isPlaying ? "1" : "0",
            snap.chapterTitle,
            hasCover ? "1" : "0"
        ].joined(separator: "|")
        guard key != widgetReloadKey else { return }
        widgetReloadKey = key
        guard snap.bookID != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "ChapterlineWidget")
    }

    private static func widgetThumbnailJPEG(from image: UIImage, maxPixel: CGFloat = 480) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth >= 1, pixelHeight >= 1 else { return nil }
        let longest = max(pixelWidth, pixelHeight)
        let ratio = longest > maxPixel ? maxPixel / longest : 1
        let size = CGSize(
            width: max(1, floor(pixelWidth * ratio)),
            height: max(1, floor(pixelHeight * ratio))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let scaled = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.82)
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
            await publishImmediate(forcePersist: true)
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            await engine.handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
            await publishImmediate()
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
            await publishImmediate(forcePersist: true)
        }
    }
}
