import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()

    private weak var controller: PlayerController?
    private var installed = false

    func install(controller: PlayerController) {
        self.controller = controller
        guard !installed else { return }
        installed = true
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.play() }
            return .success
        }
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.toggle() }
            return .success
        }

        commands.skipBackwardCommand.isEnabled = true
        commands.skipForwardCommand.isEnabled = true
        applySkipIntervals()
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.skipBack() }
            return .success
        }
        commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.skipForward() }
            return .success
        }

        // Headset double-click is nextTrack — audiobooks skip back, not next track.
        commands.nextTrackCommand.isEnabled = true
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.skipBack() }
            return .success
        }
        commands.previousTrackCommand.isEnabled = true
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.previousChapter() }
            return .success
        }

        // Keep a target so the lock-screen timeline still draws, but disable it so
        // the slider is dimmed (Audible-style). Skip buttons remain the way to move.
        commands.changePlaybackPositionCommand.isEnabled = false
        commands.changePlaybackPositionCommand.addTarget { _ in
            .commandFailed
        }

        commands.changePlaybackRateCommand.isEnabled = true
        commands.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.8, 1, 1.2, 1.5, 1.6, 1.8, 2, 2.5, 3]
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { await self?.controller?.setRate(Double(event.playbackRate)) }
            return .success
        }

        commands.stopCommand.isEnabled = true
        commands.stopCommand.addTarget { [weak self] _ in
            Task { await self?.controller?.pause() }
            return .success
        }
    }

    func applySkipIntervals() {
        let commands = MPRemoteCommandCenter.shared()
        let back = SettingsStore.shared.skipBack.secondsValue.map { NSNumber(value: $0) } ?? 15
        let forward = SettingsStore.shared.skipForward.secondsValue.map { NSNumber(value: $0) } ?? 30
        commands.skipBackwardCommand.preferredIntervals = [back as NSNumber]
        commands.skipForwardCommand.preferredIntervals = [forward as NSNumber]
    }

    func publish(_ snapshot: PlayerSnapshot, artwork: UIImage?) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = snapshot.title
        info[MPMediaItemPropertyArtist] = snapshot.author
        info[MPMediaItemPropertyAlbumTitle] = snapshot.chapterTitle
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isPlaying ? snapshot.rate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = snapshot.rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
        info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
        info[MPNowPlayingInfoPropertyChapterNumber] = snapshot.chapterIndex
        info[MPNowPlayingInfoPropertyChapterCount] = max(1, snapshot.chapters.count)
        if let artwork {
            let item = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = item
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isPlaying ? .playing : .paused
    }
}
