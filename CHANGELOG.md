# Changelog

All notable changes to Chapterline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the marketing labels used in recent commits (`v1.1`, `v1.2`, `v1.3`).

## [1.4.0] — 2026-10-07

### Added

* A Now Playing bar sits above the Library, Stats, and Settings tab bar while a book is playing or can be resumed.
* The bar shows the cover, title, and chapter or remaining time. Tap opens the existing player without restarting playback. Play resumes and Pause pauses without opening the player.

### Changed

* The Library Continue Listening card is removed. Resume lives on the Now Playing bar, including while playback is paused.

The bar has no skip or scrub. Lock Screen is unchanged. The bar hides while the player is on screen.

## [1.3.2] — 2026-09-30

### Fixed

* AudiobookBinder Pro / Apple-track M4Bs that 1.3.1 still imported as one synthetic book-title chapter now read the QuickTime text / tx3g chapter track.
* `embeddedChapters` walks every `availableChapterLocales` locale (`und` / `eng` included), not only `bestMatchingPreferredLanguages`.
* Nero timestamps are retried across 100 ns, microseconds, milliseconds, seconds, and the movie or audio timescale when the 100 ns parse yields 0–1 usable markers.
* `meta` is walked both as a FullBox and as a plain QuickTime box, so a `chpl` under either layout is visible.

### Added

* `AVAssetReader` sample parser for text / tx3g tracks, `ChapterPickPath.textTrack`, and audio `.chapterList` track associations.
* Chapter log keys `text=`, `locales=`, and `tracks=`.

A Binder export with no Chapters block and no text track is still one chapter. This release does not remux files.

## [1.3.1] — 2026-09-29

### Fixed

* Nero `chpl` version 0 (1-byte count), version 1 (4-byte count at offset 4), and the reserved-byte-before-count layout now import as real chapters. Garbage timestamps are rejected, titles are capped, and starts have to be finite and non-decreasing.
* A single AVFoundation or timed-metadata group that spans the whole file no longer hides a richer Nero chapter list.
* The MP4 box walk also looks inside `ilst` and `uuid`. 64-bit box sizes and a `moov` atom after `mdat` still work.
* Opening a book that still has exactly one chapter re-reads `.m4b` / `.m4a` chapters once per launch. Listening position stays where it was.

### Added

* Import and chapter reload log one line: `av`, `timed`, `nero`, `chosen`, and which list was used (`chapters url=<filename> …`).
* Reload chapters, in the library context menu and the player overflow. VoiceOver: “Reload chapters from file”. Confirmation is the new count (“12 chapters found” / “Still one chapter”).

A file with a broken QuickTime chapter track and no Nero `chpl` is still one chapter here. A container-only remux, which does not re-encode audio, rebuilds a table players can read:

`ffmpeg -i book.m4b -c copy -map_chapters 0 -brand "M4B " -metadata media_type=2 -f mp4 fixed.m4b`

## [1.3] — 2026-09-14

### Added

* Tappable heatmap days with a session sheet / iPad popover.
* Heatmap legend (None · 15m · 45m · 90m · 1.5h+).
* Today outline on the heatmap.
* Month ticks on Year and All heatmaps.
* Per-cell VoiceOver labels for heatmap days.

### Changed

* Year / All heatmap scrolls horizontally when the strip is wider than the card.

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
- Share extension and home-screen widget via App Group `group.com.benmonroe.ChapterLine`.
