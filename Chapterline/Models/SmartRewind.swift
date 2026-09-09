import Foundation

enum SmartRewind: Sendable {
    nonisolated static let shortPause: TimeInterval = 30
    nonisolated static let longPause: TimeInterval = 10 * 60
    nonisolated static let shortRewind: TimeInterval = 3
    nonisolated static let midRewind: TimeInterval = 20
    nonisolated static let longRewind: TimeInterval = 30

    /// Seconds to rewind after a pause of `gap`. Returns 0 when disabled or the gap is under 1s.
    nonisolated static func seconds(forGap gap: TimeInterval, enabled: Bool) -> TimeInterval {
        guard enabled, gap >= 1 else { return 0 }
        if gap < shortPause {
            return shortRewind
        }
        if gap < longPause {
            let t = (gap - shortPause) / (longPause - shortPause)
            return shortRewind + (midRewind - shortRewind) * t
        }
        return longRewind
    }

    nonisolated static func apply(
        position: TimeInterval,
        lastPauseAt: Date?,
        now: Date = Date(),
        chapterStart: TimeInterval,
        enabled: Bool
    ) -> TimeInterval {
        guard let lastPauseAt else { return position }
        let rewind = seconds(forGap: now.timeIntervalSince(lastPauseAt), enabled: enabled)
        return max(chapterStart, position - rewind)
    }
}
