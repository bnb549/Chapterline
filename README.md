# Chapterline

A local, DRM-free M4B audiobook player for iPhone. No account, no store, no ads. Offline first. Every file is a book.

## Open in Xcode

1. Open `free player.xcodeproj` (Xcode 16 / 26+).
2. Select the **free player** scheme (the product is `Chapterline.app`).
3. Pick an **iOS 17+** Simulator (iPhone) or a signed device.
4. Signing: Automatic, team `K3HHM2VAUC`, bundle `com.benmonroe.free-player`.
5. Run.

The home-screen name is **Chapterline**. The Xcode project/folder stay `free player`.

## Capabilities to enable

In the **free player** target → *Signing & Capabilities*:

| Capability | Required | Notes |
|---|---|---|
| Background Modes → **Audio** | Yes | Already set via `UIBackgroundModes` in `Info.plist` |
| **App Groups** `group.com.benmonroe.free-player` | Yes | Share extension inbox + widget snapshot |
| File Sharing (`UIFileSharingEnabled`) | Optional | Off by default. Flip in `Info.plist` if you want iTunes/Finder file sharing of `Documents/` |
| CarPlay Audio | Optional | Now Playing works without it. Library/chapter browse on a real car needs Apple’s `com.apple.developer.carplay-audio` entitlement. Simulator CarPlay does not. |

The Share extension and Widget targets must use the same App Group and the same development team.

## How to test with a sample M4B

This repo does not ship a copyrighted audiobook. Use any DRM-free `.m4b`:

1. Grab a public-domain M4B (LibriVox and Internet Archive both have them).
2. In Simulator: drag the file onto the Simulator window, or use Files → Browse → drag into Chapterline via **Import**.
3. On device: AirDrop the file to the iPhone and choose **Chapterline**, or Share → Chapterline, or Files → Open in Chapterline.

Confirm:

- Embedded chapters appear; next/prev chapter jumps correctly.
- Force-quit and reopen — playback resumes within about one second.
- Lock Screen / Control Center show title, chapter, artwork, skip back/forward.
- Speed (e.g. 1.6×) shortens remaining time.
- Sleep timer → End of chapter fades out over the last 10 seconds.
- Bookmark at the current time and jump back to it.
- Pause for a while, press play — smart rewind skips back a few seconds.

If a file has no chapters, Chapterline treats it as one chapter spanning the whole duration.

## Import notes

- Supported: `.m4b`, `.m4a`, `.mp3`, `.aac`, `.flac` (if AVFoundation can play it), `.zip` of those.
- Audible `.aa` / `.aax` is rejected. DRM-free only.
- Audio is copied into the app sandbox as-is. It is never re-encoded.
- Multiple files: you will be asked **Combine into one book** vs **Separate books**.

## Tests

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme "free player" -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Unit tests cover chapter time math, rate-adjusted remaining, smart-rewind windows, combine-files ordering, and DRM extension rejection.

## Architecture

See [AGENTS.md](AGENTS.md) for module boundaries and the v2 backlog.
