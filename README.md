# Karaoke Chan 🎤

A **cross-platform karaoke queue system** built with Flutter.

## Supported Platforms
- 🤖 Android
- 🍎 macOS
- 🪟 Windows

## Stack
| Layer | Package |
|---|---|
| UI | Flutter + Material 3 |
| State | Riverpod 2 (AsyncNotifier) |
| Routing | go_router |
| Playback | media_kit |
| Database | SQLite via sqflite / sqflite_common_ffi |
| Animations | flutter_animate |
| Fonts | google_fonts (Nunito) |

## Project Structure
```
lib/
├── main.dart
├── core/
│   ├── database/        # SQLite helper & migrations
│   ├── router/          # go_router configuration
│   ├── theme/           # AppTheme (neon dark)
│   └── widgets/         # Shared widgets (NeonCard, ScaffoldWithNav)
└── features/
    ├── home/            # Dashboard screen
    ├── library/         # Song library (import, search, delete)
    ├── queue/           # Queue management (reorder, skip, remove)
    ├── player/          # media_kit player (MiniPlayer + full PlayerScreen)
    ├── singer/          # Singer management & add-to-queue flow
    └── settings/        # App settings
```

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.3.0
- For macOS: enable entitlements (see below)
- For Windows: no extra setup

### Install & Run
```bash
flutter pub get
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run              # Android (connected device)
```

### macOS Entitlements
Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

## Development Roadmap

### ✅ Phase 1 — Foundation (Complete)
- [x] Project scaffold with correct package structure
- [x] SQLite schema (singers, songs, queue_entries, history)
- [x] Dark neon theme with Material 3
- [x] Bottom navigation with go_router ShellRoute
- [x] Riverpod 2 state management

### ✅ Phase 2 — Core Features (Complete)
- [x] Song library — import, search, delete
- [x] Queue — add, reorder (drag), remove, auto-advance
- [x] Full-screen player with seek bar + volume
- [x] Mini player at bottom of every screen
- [x] Add Singer flow with avatar color picker

### 🚧 Phase 3 — Polish
- [ ] Lyrics display (LRC file parser)
- [ ] History screen
- [ ] Singer leaderboard
- [ ] Pitch shifter / key changer (via media_kit filters)
- [ ] Background image / video for player
- [ ] Notifications for "your turn" alerts
- [ ] Export queue as PDF setlist

### 🔮 Phase 4 — Advanced
- [ ] Network streaming (YouTube URL via yt-dlp)
- [ ] Remote queue control via local Wi-Fi (HTTP API)
- [ ] Multi-room support
- [ ] Scoring system (pitch detection)
