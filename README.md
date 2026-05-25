# Karaoke-Chan 🎤

A **cross-platform karaoke queue system** built with Flutter — designed to be simple and intuitive for users of all ages.

> Scan a local folder of karaoke files, search and stream directly from YouTube, manage a unified queue, and enjoy fullscreen video playback — all from one screen.

---

## ✨ Features

### 📁 Local Library
- Recursively scans a user-selected folder for karaoke files
- Supported video formats: `.mp4`, `.mkv`, `.avi`, `.mov`, `.webm`, `.m4v`, `.wmv`, `.flv`, `.ts`
- Supported audio formats: `.mp3`, `.flac`, `.ogg`, `.wav`, `.m4a`, `.aac`, `.opus`, `.wma`, `.alac`
- Parses `"Artist - Title"` pattern automatically from filenames
- Live **file watcher** — detects files added or removed from the folder without a manual rescan
- Songs persisted to a local SQLite database

### 🌐 YouTube Streaming
- Search YouTube via the **Innertube API** (no API key, no scraping, no bot blocks)
- Toggle **Karaoke Mode** to automatically append `"karaoke"` to every YouTube search query
- Stream URLs resolved via `youtube_explode_dart` with background **pre-fetching** and a **4-hour in-memory cache**
- Automatic single retry on stream error with a freshly resolved URL
- YouTube debounce: brief network glitches (`ffurl_read`) do not incorrectly flip the play/pause icon

### 📋 Unified Queue
- Local files and YouTube videos share a **single ordered queue** (insertion order preserved)
- Tap a song to play immediately if idle, or add it to the end of the queue
- Remove any pending item from the queue individually
- **Auto-advances** to the next item when a track completes
- Play count incremented in the database for local songs after each completion
- Queue is cleared automatically on app exit / process detach

### ▶️ Player Controls
- Play / Pause / Skip
- **Seek bar** — scrub to any position with full-width progress bar and elapsed/total time display
- **Volume slider** with mute toggle — remembers the last non-zero volume for unmute restore

### 🖥️ Layout & UI
- **Wide layout** (tablet / desktop): sidebar + video area + queue panel, side by side
- **Narrow layout** (phone / Android): video at top (16:9), slim control bar, tabbed Songs / Queue view
- **Drag-to-resize sidebar** — adjust sidebar width between 26 %–50 % of the screen
- **Drag-to-resize queue panel** — adjust the queue panel height
- **Fullscreen mode** — video fills the entire screen; sidebar and queue panel are hidden

### ⌨️ Keyboard Shortcuts
| Key | Action |
|---|---|
| `F` / `F11` | Toggle fullscreen |
| `Escape` | Exit fullscreen |
| `Space` / Media Play-Pause | Toggle play / pause |
| `Cmd + →` / Media Next | Skip to next track |

### ⚙️ Settings
- **Change Karaoke Folder** — pick a new root folder to scan
- **Clear Queue** — remove all waiting entries
- **Restart App** — wipe queue data, clear the saved folder, return to folder selection

---

## 📱 Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| 🤖 Android | ✅ Supported | Forced landscape, immersive sticky (no system bars) |
| 🍎 macOS | ✅ Supported | |
| 🪟 Windows | ✅ Supported | MSIX packaged; crash log written to app support dir on unhandled error |

---

## 🛠 Tech Stack

| Layer | Package |
|---|---|
| UI | Flutter + Material 3 + `google_fonts` (Nunito) |
| State | `flutter_riverpod` 2 — `AsyncNotifier` + `riverpod_generator` codegen |
| Routing | `go_router` |
| Playback | `media_kit` + `media_kit_video` |
| Database | SQLite via `sqflite` / `sqflite_common_ffi` + `sqlite3_flutter_libs` |
| YouTube search | Innertube API (via `http`) |
| YouTube streams | `youtube_explode_dart` |
| File picking | `file_picker` |
| Permissions | `permission_handler` (Android) |
| Persistence | `shared_preferences` + `path_provider` |
| Packaging | `msix` (Windows Store), `flutter_launcher_icons` |

---

## 📁 Project Structure

```
lib/
├── main.dart                        # Bootstrap, lifecycle, crash logging
├── core/
│   ├── database/                    # DatabaseHelper (SQLite init, FFI setup)
│   ├── router/                      # go_router setup
│   ├── services/
│   │   ├── file_watcher.dart        # Live folder-change detection
│   │   ├── folder_manager.dart      # Folder pick & saved-path persistence
│   │   ├── folder_scanner.dart      # Recursive file scanner + ScannedSong model
│   │   └── youtube_service.dart     # Innertube search + stream URL resolution
│   └── theme/                       # AppTheme (dark Material 3)
└── features/
    ├── home/
    │   └── presentation/
    │       └── karaoke_stage.dart   # Main screen (sidebar + video + queue)
    ├── library/
    │   └── data/
    │       ├── library_notifier.dart        # Folder scan, file-watcher, search
    │       ├── song_model.dart              # Song entity
    │       ├── song_repository.dart         # SQLite CRUD for songs
    │       └── youtube_search_notifier.dart # YouTube search state
    ├── player/
    │   └── data/
    │       ├── player_notifier.dart  # Playback engine, queue advance, stream cache
    │       └── player_state.dart     # KaraokePlayerState + UnifiedQueueItem
    ├── queue/
    │   └── data/
    │       ├── queue_entry_model.dart  # QueueEntry entity + QueueStatus enum
    │       ├── queue_notifier.dart     # Queue state notifier
    │       └── queue_repository.dart  # SQLite CRUD for queue entries
    └── settings/
        └── presentation/
            └── settings_screen.dart  # Settings UI
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `>=3.3.0`
- Dart SDK `>=3.3.0`
- For Windows builds: MSIX signing cert configured in `pubspec.yaml`

### Install & Run

```bash
flutter pub get

flutter run               # Android (connected device)
flutter run -d macos      # macOS
flutter run -d windows    # Windows
```

### Build runner (after editing Riverpod annotated code)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Release Builds

```bash
flutter build apk --release        # Android APK
flutter build macos --release      # macOS app bundle
flutter build windows --release    # Windows executable
```

---

## 🔐 Permissions

| Permission | Platform | Reason |
|---|---|---|
| `internetClient` | Windows (MSIX) | YouTube search & stream playback |
| `privateNetworkClientServer` | Windows (MSIX) | LAN streaming fallback |
| `READ_EXTERNAL_STORAGE` / `READ_MEDIA_*` | Android | Scan karaoke files from device storage |

> **Note:** `broadFileSystemAccess` is intentionally **not** declared. `file_picker`'s `IFileOpenDialog` broker grants scoped access to the user-chosen folder automatically via the OS token, which satisfies Microsoft Store certification without requiring a restricted capability.

---

## 👤 Developer

**Mark Keshian M. Mangabay**

---

## 📄 License

© 2026 Karaoke-Chan. All rights reserved.
