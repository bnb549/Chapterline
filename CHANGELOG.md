# Changelog

All notable changes to Chapterline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the marketing labels used in recent commits (`v1.1`, `v1.2`).

## [1.2] — 2026-09-10

Commit: [`606dade`](https://github.com/bnb549/Chapterline/commit/606dadee60240990160086cb4ac48b6605b13469)

### Added
- Stable `BookIdentity` so a deleted book can reconnect when the same files are imported again.
- Chapter button on the now-playing page (replaces the boost control in that slot).
- `BookIdentityMath` plus unit tests for identity matching.

### Changed
- Delete still removes the SwiftData row and the `Documents/Books/{bookID}/` folder. Identity is what survives so a later reimport can reuse the old book ID.
- Listening position, finished state, and listening stats can attach to the reconnected identity instead of starting a new book.
- Boost remains available in Settings; it is no longer a primary player control.

### Fixed
- Reimporting a book you already listened to no longer always treats it as brand new.
- Listening stats no longer fork into a second book after delete + reimport of the same files.

## [1.1] — 2026-09-09

Commits: [`b9433e9`](https://github.com/bnb549/Chapterline/commit/b9433e9d320acc8aa20229558931decdb977da07) (stats page), [`598ff02`](https://github.com/bnb549/Chapterline/commit/598ff023bd36a5434a5a389d7bdc601d7a308eb0) (scrub toggle)

### Added
- Listening stats page.
- Optional scrub toggle on the player, with a matching Settings switch.

## [1.0] — 2026-09-09

Commit: [`e90dc0e`](https://github.com/bnb549/Chapterline/commit/e90dc0ee60b40449c713637b500e260f20d2400d)

### Added
- Local, DRM-free audiobook player for iPhone. No account, no store, no ads.
- Import `.m4b`, `.m4a`, `.mp3`, `.aac`, `.flac` (when AVFoundation can play it), and zips of those.
- Explicit rejection of Audible `.aa` / `.aax`.
- Embedded chapter support; files with no chapters treated as one chapter spanning the duration.
- Background audio, Lock Screen / Control Center Now Playing, skip back/forward, speed, sleep timer (end of chapter with fade), bookmarks, smart rewind.
- Combine multiple files into one book or import them as separate books.
- Share extension and home-screen widget via App Group `group.com.benmonroe.free-player`.
