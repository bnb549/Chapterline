import Foundation

enum TimeMath: Sendable {
    nonisolated static func remaining(duration: TimeInterval, position: TimeInterval, rate: Double) -> TimeInterval {
        let safeRate = rate > 0 ? rate : 1
        return max(0, duration - position) / safeRate
    }

    nonisolated static func progress(duration: TimeInterval, position: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    nonisolated static func chapterIndex(at position: TimeInterval, in chapters: [ChapterMarker]) -> Int {
        guard !chapters.isEmpty else { return 0 }
        var result = 0
        for (index, chapter) in chapters.enumerated() {
            if position + 0.05 >= chapter.start {
                result = index
            } else {
                break
            }
        }
        return result
    }

    nonisolated static func chapter(at position: TimeInterval, in chapters: [ChapterMarker]) -> ChapterMarker? {
        guard !chapters.isEmpty else { return nil }
        return chapters[chapterIndex(at: position, in: chapters)]
    }

    nonisolated static func nextChapterStart(at position: TimeInterval, in chapters: [ChapterMarker]) -> TimeInterval? {
        let index = chapterIndex(at: position, in: chapters)
        let next = index + 1
        guard next < chapters.count else { return nil }
        return chapters[next].start
    }

    nonisolated static func previousChapterStart(at position: TimeInterval, in chapters: [ChapterMarker]) -> TimeInterval? {
        guard !chapters.isEmpty else { return nil }
        let index = chapterIndex(at: position, in: chapters)
        let current = chapters[index]
        if position - current.start > 3, index >= 0 {
            return current.start
        }
        if index > 0 {
            return chapters[index - 1].start
        }
        return 0
    }

    /// Maps a book-absolute time onto (file index, local time).
    nonisolated static func fileLocation(absoluteTime: TimeInterval, fileDurations: [TimeInterval]) -> (index: Int, localTime: TimeInterval) {
        guard !fileDurations.isEmpty else { return (0, 0) }
        var remaining = max(0, absoluteTime)
        for (index, duration) in fileDurations.enumerated() {
            let isLast = index == fileDurations.count - 1
            if remaining < duration || isLast {
                let local = isLast ? min(remaining, max(0, duration)) : remaining
                return (index, max(0, local))
            }
            remaining -= duration
        }
        let last = fileDurations.count - 1
        return (last, fileDurations[last])
    }

    nonisolated static func absoluteTime(fileIndex: Int, localTime: TimeInterval, fileDurations: [TimeInterval]) -> TimeInterval {
        let prefix = fileDurations.prefix(max(0, fileIndex)).reduce(0, +)
        return prefix + max(0, localTime)
    }

    nonisolated static func format(duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    nonisolated static func formatRemaining(duration: TimeInterval, position: TimeInterval, rate: Double) -> String {
        let remaining = remaining(duration: duration, position: position, rate: rate)
        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        if minutes > 0 {
            return "\(minutes)m left"
        }
        return "\(total)s left"
    }
}

struct ChapterMarker: Equatable, Sendable, Hashable {
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
    var source: ChapterSource

    var end: TimeInterval { start + duration }
}
