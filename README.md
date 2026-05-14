# Karaoke-Chan 🎤

A **cross-platform karaoke queue system** built with Flutter — designed to be simple and intuitive for users of all ages.

> Play local karaoke files or stream directly from YouTube, manage a queue, and enjoy fullscreen playback — all from one screen.

---

## ✨ Features

- 🎵 **Local library** — scan a folder, browse and queue MP4, MKV, AVI, MP3, FLAC, and more
- 🌐 **YouTube streaming** — search YouTube and stream karaoke videos without downloading
- 📋 **Mixed queue** — local files and YouTube videos in one unified queue with auto-advance
- ▶️ **Always-visible player controls** — play/pause and skip always on screen, never hidden
- 🔊 **Volume control** — adjust volume inline with the player controls
- ⏩ **Seek bar** — scrub through any song with a full-width progress bar and time display
- 🖥️ **Fullscreen mode** — immersive video playback with a fade-in overlay for controls
- 📐 **Drag-to-resize queue panel** — resize the queue list to fit your preference
- ⚙️ **Settings panel** — change folder, clear queue, or restart from the sidebar

---

## 📱 Supported Platforms

| Platform | Status |
|---|---|
| 🤖 Android | ✅ Supported |
| 🍎 macOS | ✅ Supported |
| 🪟 Windows | ✅ Supported |

---

## 🛠 Tech Stack

| Layer | Package |
|---|---|
| UI | Flutter + Material 3 |
| State | Riverpod 2 (`AsyncNotifier` + codegen) |
| Playback | media_kit + media_kit_video |
| Database | SQLite via sqflite / sqflite_common_ffi |
| YouTube | youtube_explode_dart |
| File picking | file_picker |
| Permissions | permission_handler (Android) |
| Persistence | shared_preferences |

---

## 📁 Project Structure

```
lib/
├── main.dart
├── core/
│   ├── database/        # SQLite helper & migrations
│   └── services/        # YouTube service
└── features/
    ├── home/            # Main screen (KaraokeStage — video + sidebar + queue)
    ├── library/         # Song library (scan, search, YouTube search)
    ├── queue/           # Queue management (entries, status, auto-advance)
    ├── player/          # media_kit player state & notifier
    └── settings/        # Settings screen
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK ≥ 3.3.0
- Dart SDK ≥ 3.3.0
- For macOS: entitlements configured (see below)

### Install & Run

```bash
flutter pub get
flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run               # Android (connected device)
```

### macOS Entitlements

Add to both `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

---

## 📦 Build

```bash
# Android APK
flutter build apk --release

# macOS app bundle
flutter build macos --release

# Windows executable
flutter build windows --release
```

---

## 📋 Changelog

### v1.0.0 — May 2026
- ✅ Initial release
- ✅ Local file library with folder scanning
- ✅ YouTube search and streaming via `youtube_explode_dart`
- ✅ Mixed local + YouTube queue with auto-advance
- ✅ Always-visible player control bar (play/pause, skip, volume, seek)
- ✅ Fullscreen video mode with fade-in overlay controls
- ✅ Drag-to-resize queue panel
- ✅ Sidebar with search, settings, folder picker
- ✅ Accessible UI — large tap targets and labeled buttons

---

## 🗺 Roadmap

### 🚧 Planned
- [ ] Lyrics display (LRC file parser + sync)
- [ ] Pitch shifter / key changer (via media_kit audio filters)
- [ ] Queue history screen
- [ ] Remote queue control over local Wi-Fi (HTTP API)
- [ ] Export queue as PDF setlist

### 🔮 Future
- [ ] Scoring system (pitch detection)
- [ ] Multi-room / multi-screen support
- [ ] Singer management (turn-based queue per singer)
- [ ] "Your turn" notifications

---

## 👤 Developer

**Mark Keshian M. Mangabay**

---

## 📄 License

© 2026 Karaoke-Chan. All rights reserved.
