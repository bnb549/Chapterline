# VERSION

App: Chapterline
Bundle ID: com.benmonroe.free-player
Platforms: iOS 17+ / iPadOS 17+
Xcode: 16+
Swift: 6
Marketing version source of truth: this file + Xcode MARKETING_VERSION
Build number source of truth: Xcode CURRENT_PROJECT_VERSION (integer, monotonic)

## Current

- Marketing: 1.3
- Build: 2
- Channel: local
- Date: 2026-09-14
- Git: main / 2c1cd0e

## SemVer rules

- MAJOR: breaking UI/data/file-format changes, or dropped OS support
- MINOR: user-visible features that stay backward compatible
- PATCH: fixes, polish, performance, copy
- Build number: increment on every archive / TestFlight upload, even if marketing version is unchanged

## History

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
