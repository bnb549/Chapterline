# Chapterline — agent conventions

Local, DRM-free audiobook player. Not a music player. Every file is a book.

Display name: **Chapterline**. Xcode project/folder stay `free player`. Swift module: `Chapterline`. Bundle ID: `com.benmonroe.free-player`.

## Layout (MV)

```
free player/                 # app target (PBXFileSystemSynchronizedRootGroup)
  Models/                    # SwiftData types + pure math
  Services/                  # playback, import, persistence, system bridges
  Features/                  # SwiftUI: Library, Player, Settings, Import
ChapterlineTests/            # unit tests
ChapterlineShare/            # share extension
ChapterlineWidget/           # home-screen widget
```

No ViewModels folder. Views talk to `@Observable` stores via `Environment`. Do not put `AVPlayer` in SwiftUI views.

## Module boundaries

| Type | Owns | Must not |
|---|---|---|
| `LibraryStore` | import, delete, rename, folders, finished, artwork override | AVPlayer |
| `ChapterService` | parse + persist chapters, reload | playback |
| `BookmarkStore` | CRUD + jump timestamps | player internals |
| `AudioPlayerService` (actor) | rate, position, chapter index, sleep timer, smart rewind, queue | SwiftUI, SwiftData writes |
| `PlayerController` | MainActor snapshot of the player for UI | file I/O |
| `NowPlayingBridge` | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | library mutations except position-save callback |
| `ImportPipeline` | Files / share / zip / folder-of-files → Book | UI layout |
| `SettingsStore` | skip, speed, rewind, fade, boost, appearance, hide remaining | per-book position |
| `CarPlayBridge` / `CarPlaySceneDelegate` | CarPlay templates | SwiftUI |

`AppRuntime` is the process-wide handle so CarPlay, App Intents, and the widget URL path can reach the same stores. Set it in `ChapterlineApp.init`.

## Product rules

- DRM-free only. Reject `.aa` / `.aax` with an explicit message. Do not attempt Audible.
- Do not re-encode audio on import. `FileManager.copyItem` into `Documents/Books/{bookID}/`.
- Do not shuffle, loop-album, or treat chapters as music tracks.
- Remaining time is `(duration - position) / rate`.
- Progress lives in SwiftData (Application Support). Audio files live in Documents. Both survive binary offload.
- Headset double-click (`nextTrackCommand`) skips **back**, not next track.
- Skip intervals are independent for back vs forward: 15 / 30 / 45 / 60 seconds or Chapter.
- Default skip-back 15s, skip-forward 30s.
- VoiceOver must announce book title, chapter title, remaining time, and speed.
- Large tap targets (44pt+). Usable one-handed.

## Persistence

- SwiftData store: `Application Support/Chapterline/Chapterline.store`
- Audio + extracted cover: `Documents/Books/{uuid}/`
- App Group `group.com.benmonroe.free-player`: share Inbox + Now Playing snapshot for the widget
- Write `Book.position` every ~1s while playing, and immediately on pause, skip, chapter jump, route change, background, terminate
- Deleting a book deletes the SwiftData row **and** its Documents folder
- Finished books stay until the user deletes them

## Isolation

- Project setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on. Leave it.
- `AudioPlayerService` is an `actor` (actors are not MainActor). Hop snapshots to `PlayerController` with `await`.
- SwiftData models and SwiftUI views stay on the main actor.
- Import, chapter parse, zip unzip, artwork extract: off the main thread. Never load a 20-hour file into memory.

## Allowed extras

- **ZIPFoundation** via SPM — unzip import only. Apple has no Zip API. Do not pull a full audio-kit framework.
- No analytics, no tracking SDKs, no accounts, no store.

## UI

- Dark is the default. Cover-tinted player chrome is fine. Launch screen follows system light/dark so it does not flash against the chosen theme.
- Appearance: system / light / dark / OLED (true black).
- Book detail and player are **one page**. Do not add a separate Now Playing route.
- Dynamic Type. VoiceOver labels on every control.

## v2 backlog — do not implement

- iCloud progress sync
- Apple Watch standalone playback
- Audiobookshelf / Jellyfin / Dropbox streaming
- Hardcover sync
- Silence skip
- On-device AI recaps
- Public-domain catalogs
- Account, recommendations, social
