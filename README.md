# Chapterline

**A local, DRM-free audiobook player for iPhone.**

No account. No store. No ads. Offline first. Every file is a book.

Chapterline plays the audiobooks you already own. Import a file, pick up where you left off, jump chapters, bookmark a line, and keep listening from the Lock Screen. It is not a music player and it is not a catalog. Your library lives on the device.

## What it does

- Plays DRM-free audiobooks on iPhone (iOS 17+)
- Treats each import as a **book**, not a playlist of tracks
- Reads **embedded chapters** from M4B and similar files
- Remembers position across force-quit, background, and lock
- Shows title, chapter, artwork, and skip controls on the Lock Screen and in Control Center
- Lets you listen at a custom speed with remaining time that matches that speed
- Sleeps at the **end of the chapter**, fading out over the last 10 seconds
- Bookmarks the current time and jumps back to it
- Smart-rewinds a few seconds when you resume after a pause
- Combines several files into one book, or imports them as separate books
- Tracks listening stats and reconnects them if you delete a book and later import the same files again. The stats heatmap is a tappable day grid with a legend and a session list for each day.

## What you can import

Supported formats:

- `.m4b` (preferred)
- `.m4a`, `.mp3`, `.aac`
- `.flac` when AVFoundation can play it
- `.zip` archives of the above

**Not supported:** Audible `.aa` / `.aax`. Those files are rejected on purpose. Chapterline does not unlock or stream DRM.

Audio is copied into the app sandbox as-is. It is never re-encoded.

## How listening works

- Book detail and the player are **one page** — no separate Now Playing route
- Next / previous chapter uses the embedded chapter list
- Files with no chapters are treated as a single chapter spanning the whole duration
- Skip back and skip forward are independent (defaults: 15s back, 30s forward; or skip by chapter)
- Headset double-click skips **back**, not to the next track
- Optional scrubber on the player (also a Settings switch)
- Appearance: system, light, dark, or OLED true black (dark is the default)
- VoiceOver announces book title, chapter title, remaining time, and speed

## Getting files onto the phone

Use any DRM-free file you own. Public-domain M4Bs from LibriVox or the Internet Archive work well for testing.

- **Share sheet** — AirDrop or Share → Chapterline
- **Files** — Open in Chapterline, or use Import in the app
- **Simulator** — drag a file onto the Simulator window

Multiple files in one drop: you will be asked **Combine into one book** vs **Separate books**.

## What it is not

Chapterline does not include an account, recommendations, social features, a store, analytics, or streaming from Audible / Audiobookshelf / iCloud. Progress lives on the device. Companion Mac tooling for building chaptered M4Bs (ChapterBinder) is a separate project.

See [CHANGELOG.md](CHANGELOG.md) for version history and [AGENTS.md](AGENTS.md) for architecture and product rules.

---

## Open in Xcode

1. Open `Chapterline.xcodeproj` (Xcode 16 / 26+). Older checkouts may still show `free player.xcodeproj`.
2. Select the app scheme (the product is `Chapterline.app`).
3. Pick an **iOS 17+** Simulator (iPhone) or a signed device.
4. Signing: Automatic, team `K3HHM2VAUC`, bundle `com.benmonroe.free-player`.
5. Run.

The home-screen name is **Chapterline**. The Swift module is `Chapterline`. The bundle ID remains `com.benmonroe.free-player`.

### Capabilities

In the app target → *Signing & Capabilities*:

| Capability | Required | Notes |
|---|---|---|
| Background Modes → **Audio** | Yes | Already set via `UIBackgroundModes` in `Info.plist` |
| **App Groups** `group.com.benmonroe.free-player` | Yes | Share extension inbox + widget snapshot |
| File Sharing (`UIFileSharingEnabled`) | Optional | Off by default. Flip in `Info.plist` for Finder access to `Documents/` |
| CarPlay Audio | Optional | Now Playing works without it. Library/chapter browse in a car needs Apple’s `com.apple.developer.carplay-audio` entitlement. Simulator CarPlay does not. |

The Share extension and Widget targets must use the same App Group and the same development team.

### Tests

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme "Chapterline" -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If the scheme is still named `free player` in your checkout, use that name instead.

Unit tests cover chapter time math, rate-adjusted remaining time, smart-rewind windows, combine-files ordering, DRM extension rejection, and book identity matching.
