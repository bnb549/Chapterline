# VERSION

App: Chapterline
Bundle ID: com.benmonroe.ChapterLine
Platforms: iOS 17+ / iPadOS 17+
Xcode: 16+
Swift: 6
Marketing version source of truth: this file + Xcode MARKETING_VERSION
Build number source of truth: Xcode CURRENT_PROJECT_VERSION (integer, monotonic)

## Current

- Marketing: 1.4.0
- Build: 6
- Channel: App Store prep
- Date: 2026-10-07
- Git: feature/now-playing-bar-1.4.0 (bnb549/Chapterline)
- App, share extension, and widget all ship as 1.4.0 (6)

## SemVer rules

- MAJOR: breaking UI/data/file-format changes, or dropped OS support
- MINOR: user-visible features that stay backward compatible
- PATCH: fixes, polish, performance, copy
- Build number: increment on every archive / TestFlight upload, even if marketing version is unchanged

## History

### 1.4.0 — 2026-10-07 — build 6

- MINOR. A Now Playing bar sits above the Library / Stats / Settings tab bar for the book that is playing or the unfinished book you can resume.
- The Library Continue Listening card is removed. Play on the bar resumes that book without opening the player. Pause pauses without opening it. A tap on the bar opens the existing player without restarting playback.
- The caption is Now Playing while audio is running and Continue Listening while paused. The bar shows cover, title, and chapter or remaining time.
- Known limits: no skip or scrub on the bar. Lock Screen is unchanged. The bar hides while the player is on screen.
- Files touched: LibraryView.swift, StatsView.swift, SettingsView.swift, RootView.swift, NowPlayingBar.swift, BookPlayerView.swift, PlayerController.swift, project.pbxproj, CHANGELOG.md, VERSION.md.

### 1.3.2 — 2026-10-05 — build 5

- Build bump for App Store submission. Marketing version stays 1.3.2.
- Share extension and widget marketing version moved from 1.0 (1) to 1.3.2 (5), matching the app.

### 1.3.2 — 2026-09-30 — build 4

- PATCH. Apple-track / AudiobookBinder Pro M4Bs that 1.3.1 still imported as one synthetic book-title chapter now read the QuickTime text / tx3g chapter track.
- Fixed: `embeddedChapters` walks every `availableChapterLocales` locale (`und` / `eng` included), not only `bestMatchingPreferredLanguages`.
- Added: `AVAssetReader` sample parser for text / tx3g tracks; `ChapterPickPath.textTrack`; follow audio `.chapterList` associations.
- Fixed: Nero timestamp retry across 100 ns / µs / ms / seconds / movie-audio timescale when the 100 ns parse yields 0–1 usable markers.
- Fixed: `meta` walked as both FullBox and not, so a `chpl` under QuickTime `meta` is visible.
- Added: log keys `text=`, `locales=`, `tracks=`.
- Known limits: a Binder export with no Chapters block and no text track is still one chapter. This PATCH does not remux files.

### 1.3.1 — 2026-09-29 — build 3

- PATCH. AudiobookBinder Pro / ffmpeg-style M4Bs that store Nero `chpl` (or a dummy QuickTime group plus a real `chpl` table) import with their real chapter list.
- Fixed: `parseNero` version 0 (1-byte count), version 1 (4-byte count at offset 4), reserved-byte variant; reject insane timestamps; cap titles; require non-decreasing starts.
- Fixed: a single AVFoundation or timed-metadata group that spans the whole file no longer blocks the Nero walker. Richer valid list wins.
- Fixed: box walk also recurses `ilst` and `uuid`; still handles 64-bit sizes and `moov` after `mdat`.
- Added: one-line import/reload log (`av` / `timed` / `nero` / `chosen` / `path`).
- Added: one-shot chapter reload on open when a book currently has exactly one chapter; explicit Reload chapters action.
- Known limits: QuickTime text tracks without a valid `tref/chap` are still invisible to AVFoundation; this PATCH does not parse QT samples itself. One-file Binder exports that truly contain a single 0→end marker stay one chapter. Already-imported multi-chapter books are not re-parsed automatically.
- Files touched: `ChapterService.swift`, `MP4ChapterParser.swift`, library/player reload hook, `PlayerSheets.swift` (SwiftData import), `ChapterlineTests/MP4ChapterParserTests.swift`, `ChapterlineTests/ChapterServiceFallbackTests.swift`, `CHANGELOG.md`, `VERSION.md`.

### 1.3 — 2026-09-14 — build 2

- Heatmap days are tappable. Sheet/popover shows that day's wall time and sessions that started that day; a row opens the book the same way Recent sessions does.
- VoiceOver: each cell is a button labeled like “Tuesday, September 8, 1 hour 12 minutes”.
- Legend under the chart: None · 15m · 45m · 90m · 1.5h+.
- Today cell is outlined.
- Year / All show locale month ticks; Today / 7 days hide the X axis.
- Known limits: sessions still bucket by start day only (no midnight split); no per-day delete; no custom bucket colors.
- Files touched: Stats heatmap UI, ListeningStatsStore.sessionsStarted, ListeningStatsMath.formatSpoken, tests, CHANGELOG.md, VERSION.md

### 1.2 — 2026-09-10

- Stable BookIdentity; chapter button on now-playing; listening stats reconnect after delete + reimport.

### 1.1 — 2026-09-09

- Listening stats page; optional scrub toggle.

### 1.0 — 2026-09-09

- Local DRM-free audiobook player.
