// lib/features/home/presentation/karaoke_stage.dart
//
// Layout matches the HTML mockup:
//  ┌──────────────┬──────────────────────────────────┐
//  │  SIDEBAR 35% │  VIDEO AREA (flex)     [⛶]       │
//  │  🎤 title    │                                   │
//  │  [search]    │  video / audio placeholder        │
//  │  song list   │  ┌─NOW PLAYING──────────────────┐ │
//  │  [QUEUE btn] │  │ title · artist  ⏯ ⏭         │ │
//  │              │  │ UP NEXT: …                   │ │
//  │              │  └──────────────────────────────┘ │
//  │              ├──────────────────────────────────┤
//  │              │  QUEUE PANEL (220px)              │
//  └──────────────┴──────────────────────────────────┘
//  Fullscreen → sidebar + queue panel hidden, video fills screen.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:karaoke_chan/core/services/youtube_service.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/youtube_search_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

// ── Search mode ──────────────────────────────────────────────────────────────
enum SearchMode { local, online }

// ── Design tokens (match HTML) ───────────────────────────────────────────────
const _bg = Color(0xFF111827);
const _sidebarBg = Color(0xFF1F2937);
const _border = Color(0xFF374151);
const _cardBg = Color(0xFF374151);
const _cardHover = Color(0xFF4B5563);
const _queueGreen = Color(0xFF22C55E);
const _sub = Color(0xFFCBD5E1);
const _overlayBg = Color(0xB3000000);
const _purple = Color(0xFFE040FB);

// ─────────────────────────────────────────────────────────────────────────────

class KaraokeStage extends ConsumerStatefulWidget {
  const KaraokeStage({super.key});

  @override
  ConsumerState<KaraokeStage> createState() => _KaraokeStageState();
}

class _KaraokeStageState extends ConsumerState<KaraokeStage> {
  final _search = TextEditingController();
  final _focusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  bool _fullscreen = false;
  bool _isChangingFolder = false;
  bool _showSettings = false;
  double? _sidebarWidth;
  double _queueHeight = 220;
  SearchMode _searchMode = SearchMode.local;
  Timer? _ytDebounce;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _ytDebounce?.cancel();
    _search.dispose();
    _searchFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setFullscreen(bool value) {
    debugPrint(
        '[Fullscreen] _setFullscreen called: value=$value, current=$_fullscreen');
    setState(() => _fullscreen = value);
    debugPrint('[Fullscreen] setState done: _fullscreen=$_fullscreen');
  }

  void _toggleFullscreen() {
    debugPrint(
        '[Fullscreen] _toggleFullscreen called: current=$_fullscreen -> next=${!_fullscreen}');
    _setFullscreen(!_fullscreen);
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Don't steal keyboard shortcuts while the search bar is focused.
    if (_searchFocusNode.hasFocus) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _fullscreen) {
      _setFullscreen(false);
      return true;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      ref.read(playerProvider.notifier).togglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.arrowRight &&
            HardwareKeyboard.instance.isMetaPressed) {
      ref.read(playerProvider.notifier).skip();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final playerAsync = ref.watch(playerProvider);
    final queueAsync = ref.watch(queueNotifierProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _bg,
      body: libraryAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _purple)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white70))),
        data: (library) {
          if (!library.hasFolder || _isChangingFolder) {
            return _FolderPickerView(
              onPick: () async {
                await ref.read(libraryProvider.notifier).pickFolder();
                if (mounted) setState(() => _isChangingFolder = false);
              },
              onCancel: library.hasFolder
                  ? () => setState(() => _isChangingFolder = false)
                  : null,
            );
          }
          if (library.isScanning) {
            return _ScanningView(library: library);
          }
          if (library.status == ScanStatus.error) {
            return _ScanErrorView(
              message: library.errorMessage ?? 'Unknown scan error',
              onRetry: () => ref.read(libraryProvider.notifier).pickFolder(),
            );
          }

          final player = playerAsync.valueOrNull ?? const KaraokePlayerState();
          final queue = queueAsync.valueOrNull ?? [];

          return Row(
            children: [
              if (!_fullscreen) ...[
                _Sidebar(
                  library: library,
                  searchCtrl: _search,
                  searchFocusNode: _searchFocusNode,
                  sidebarWidth:
                      _sidebarWidth ?? MediaQuery.sizeOf(context).width * 0.35,
                  currentSongId: player.currentEntry?.songId,
                  queuedSongIds: queue
                      .where((e) =>
                          e.status == QueueStatus.waiting ||
                          e.status == QueueStatus.playing)
                      .map((e) => e.songId)
                      .toSet(),
                  onQueue: (s) => _queueSong(s, player),
                  onChangeFolder: () =>
                      setState(() => _isChangingFolder = true),
                  searchMode: _searchMode,
                  onSearchModeChanged: (mode) {
                    setState(() {
                      _searchMode = mode;
                      _ytDebounce?.cancel();
                      // Re-run the current query in the new mode without clearing the text.
                      final q = _search.text;
                      if (mode == SearchMode.local) {
                        ref.read(youtubeSearchProvider.notifier).clear();
                        ref.read(libraryProvider.notifier).search(q);
                      } else {
                        ref.read(libraryProvider.notifier).search('');
                        if (q.isNotEmpty) {
                          ref.read(youtubeSearchProvider.notifier).search(q);
                        } else {
                          ref.read(youtubeSearchProvider.notifier).clear();
                        }
                      }
                    });
                  },
                  onYoutubeSearch: (q) {
                    _ytDebounce?.cancel();
                    _ytDebounce = Timer(const Duration(milliseconds: 600), () {
                      ref.read(youtubeSearchProvider.notifier).search(q);
                    });
                  },
                  onYoutubePlay: (video) => _queueYoutube(video, player),
                  showSettings: _showSettings,
                  onToggleSettings: () =>
                      setState(() => _showSettings = !_showSettings),
                ),
                // ── Sidebar drag resizer ──────────────────────────────
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      final screenW = MediaQuery.sizeOf(context).width;
                      setState(() {
                        _sidebarWidth =
                            ((_sidebarWidth ?? screenW * 0.35) + d.delta.dx)
                                .clamp(220.0, screenW * 0.50);
                      });
                    },
                    child: Container(
                      width: Platform.isAndroid ? 18 : 6,
                      color: _border,
                      child: Platform.isAndroid
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  4,
                                  (_) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF9CA3AF),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _VideoArea(
                        player: player,
                        queue: queue,
                        fullscreen: _fullscreen,
                        onToggle: () => _toggleFullscreen(),
                      ),
                    ),
                    if (!_fullscreen) ...[
                      // ── Queue panel drag resizer ────────────────────
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: GestureDetector(
                          onVerticalDragUpdate: (d) {
                            final screenH = MediaQuery.sizeOf(context).height;
                            setState(() {
                              _queueHeight = (_queueHeight - d.delta.dy)
                                  .clamp(150.0, screenH * 0.55);
                            });
                          },
                          child: Container(
                            height: Platform.isAndroid ? 18 : 4,
                            color: _border,
                            child: Platform.isAndroid
                                ? Center(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        4,
                                        (_) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2),
                                          child: Container(
                                            width: 4,
                                            height: 4,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF9CA3AF),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      _QueuePanel(queue: queue, height: _queueHeight),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _queueSong(Song song, KaraokePlayerState player) {
    if (song.id == null) return;
    if (player.isIdle) {
      ref.read(playerProvider.notifier).playNow(song);
    } else {
      ref.read(playerProvider.notifier).queueLocal(song);
      _showQueuedSnackBar(song.title);
    }
  }

  void _queueYoutube(YoutubeVideoResult video, KaraokePlayerState player) {
    if (player.isIdle) {
      ref.read(playerProvider.notifier).playYoutube(video);
    } else {
      ref.read(playerProvider.notifier).queueYoutube(video);
      _showQueuedSnackBar(video.title);
    }
  }

  void _showQueuedSnackBar(String title) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF059669)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            const Icon(Icons.queue_music, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Added to Queue',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Folder picker ────────────────────────────────────────────────────────────

class _FolderPickerView extends StatelessWidget {
  const _FolderPickerView({required this.onPick, this.onCancel});
  final VoidCallback onPick;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black54,
                          blurRadius: 30,
                          offset: Offset(0, 10)),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/icons/applogo.png',
                        height: 80, width: 80),
                    const Gap(16),
                    const Text('Karaoke-Chan',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const Gap(12),
                    const Text(
                      'Please select a folder to browse your songs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _sub, fontSize: 15, height: 1.5),
                    ),
                    const Gap(32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onPick,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _queueGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('📁  Select Karaoke Folder'),
                      ),
                    ),
                    if (onCancel != null) ...[
                      const Gap(12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white54,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 15)),
                        ),
                      ),
                    ],
                    const Gap(16),
                    const Text(
                        'Supports MP4 · MKV · AVI · MP3 · FLAC · and more',
                        style: TextStyle(color: Colors.white30, fontSize: 12)),
                  ]), // Column
                ), // inner Container
              ), // ConstrainedBox
            ), // inner Center
          ), // SingleChildScrollView
        ), // outer Center
      ), // SafeArea
    ); // outer Container
  }
}

// ── Scanning ─────────────────────────────────────────────────────────────────

class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.library});
  final LibraryState library;

  @override
  Widget build(BuildContext context) {
    final progress = library.totalCount > 0
        ? library.scannedCount / library.totalCount
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.radar, color: _purple, size: 48),
          const Gap(20),
          const Text('Scanning Folder…',
              style: TextStyle(
                  color: _purple, fontSize: 22, fontWeight: FontWeight.bold)),
          const Gap(8),
          Text('${library.scannedCount} songs found',
              style: const TextStyle(color: _sub)),
          const Gap(20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(_purple),
            ),
          ),
          const Gap(8),
          Text(library.folderPath ?? '',
              style: const TextStyle(color: Colors.white30, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ── Scan error ────────────────────────────────────────────────────────────────

class _ScanErrorView extends ConsumerWidget {
  const _ScanErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 52),
          const Gap(20),
          const Text('Scan Failed',
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const Gap(12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _sub, fontSize: 14)),
          const Gap(32),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: _queueGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose Folder Again',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.library,
    required this.searchCtrl,
    required this.searchFocusNode,
    required this.sidebarWidth,
    required this.currentSongId,
    required this.queuedSongIds,
    required this.onQueue,
    required this.onChangeFolder,
    required this.searchMode,
    required this.onSearchModeChanged,
    required this.onYoutubeSearch,
    required this.onYoutubePlay,
    required this.showSettings,
    required this.onToggleSettings,
  });

  final LibraryState library;
  final TextEditingController searchCtrl;
  final FocusNode searchFocusNode;
  final double sidebarWidth;
  final int? currentSongId;
  final Set<int> queuedSongIds;
  final void Function(Song) onQueue;
  final VoidCallback onChangeFolder;
  final SearchMode searchMode;
  final void Function(SearchMode) onSearchModeChanged;
  final void Function(String query) onYoutubeSearch;
  final void Function(YoutubeVideoResult video) onYoutubePlay;
  final bool showSettings;
  final VoidCallback onToggleSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: sidebarWidth,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _sidebarBg,
          border: Border(right: BorderSide(color: _border, width: 2)),
        ),
        child: SafeArea(
          right: false,
          child: Column(children: [
            // ── Top bar ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _border, width: 2))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Image.asset(
                        'assets/icons/applogo.png',
                        height: 28,
                        width: 28,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Karaoke-Chan',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                      IconButton(
                        icon: Icon(
                          showSettings ? Icons.close : Icons.settings_outlined,
                          color: showSettings ? Colors.white70 : Colors.white38,
                          size: 18,
                        ),
                        tooltip: showSettings ? 'Close Settings' : 'Settings',
                        onPressed: onToggleSettings,
                      ),
                      if (!showSettings)
                        IconButton(
                          icon: const Icon(Icons.folder_open_outlined,
                              color: Colors.white38, size: 18),
                          tooltip: 'Change folder',
                          onPressed: onChangeFolder,
                        ),
                    ]),
                    if (!showSettings) ...[
                      const Gap(12),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: searchCtrl,
                        builder: (context, value, _) => TextField(
                          controller: searchCtrl,
                          focusNode: searchFocusNode,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: searchMode == SearchMode.online
                                ? 'Search on YouTube...'
                                : 'Search songs...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.white38),
                            suffixIcon: value.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white38, size: 18),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      ref
                                          .read(libraryProvider.notifier)
                                          .search('');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: _cardBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                          onChanged: (q) {
                            if (searchMode == SearchMode.local) {
                              ref.read(libraryProvider.notifier).search(q);
                            } else {
                              onYoutubeSearch(q);
                            }
                          },
                        ),
                      ),
                      const Gap(10),
                      _SearchModeToggle(
                        mode: searchMode,
                        onChanged: onSearchModeChanged,
                      ),
                    ],
                  ]),
            ),

            // ── Body: Settings panel OR Song list ──────────────────────────
            if (showSettings)
              Expanded(
                child: _SidebarSettingsPanel(
                  onChangeFolder: onChangeFolder,
                  onClose: onToggleSettings,
                ),
              )
            else
              Expanded(
                child: searchMode == SearchMode.online
                    ? _OnlineResultsList(onPlay: onYoutubePlay)
                    : library.songs.isEmpty
                        ? const Center(
                            child: Text('No songs found',
                                style: TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(15, 15, 15, 64),
                            itemCount: library.songs.length,
                            itemBuilder: (_, i) => _SongItem(
                              song: library.songs[i],
                              isCurrent: library.songs[i].id == currentSongId,
                              isQueued: library.songs[i].id != null &&
                                  queuedSongIds.contains(library.songs[i].id),
                              onQueue: () => onQueue(library.songs[i]),
                            ),
                          ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Sidebar settings panel ───────────────────────────────────────────────────

class _SidebarSettingsPanel extends ConsumerWidget {
  const _SidebarSettingsPanel({
    required this.onChangeFolder,
    required this.onClose,
  });
  final VoidCallback onChangeFolder;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Library ─────────────────────────────────────────────────────
        const _SettingsSectionLabel(label: 'Library'),
        const Gap(8),
        _SettingsItem(
          icon: Icons.folder_open,
          iconColor: _queueGreen,
          title: 'Change Karaoke Folder',
          subtitle: 'Pick a different root folder to scan',
          onTap: () {
            ref.read(libraryProvider.notifier).changeFolder();
          },
        ),
        const Gap(6),
        _SettingsItem(
          icon: Icons.restart_alt,
          iconColor: Colors.orangeAccent,
          title: 'Restart App',
          subtitle: 'Clear all cache and return to folder selection',
          onTap: () => _confirmRestart(context, ref),
        ),
        const Gap(20),

        // ── Queue ────────────────────────────────────────────────────────
        const _SettingsSectionLabel(label: 'Queue'),
        const Gap(8),
        _SettingsItem(
          icon: Icons.cleaning_services,
          iconColor: Colors.redAccent,
          title: 'Clear Queue',
          subtitle: 'Remove all waiting entries',
          onTap: () => _confirmClearQueue(context, ref),
        ),
        const Gap(20),

        // ── About ────────────────────────────────────────────────────────
        const _SettingsSectionLabel(label: 'About'),
        const Gap(8),
        const _SettingsItem(
          icon: Icons.mic,
          iconColor: _purple,
          title: 'Karaoke-Chan  v1.0.0',
          subtitle: 'Local & Online Karaoke Player',
        ),
        const Gap(6),
        const _SettingsItem(
          icon: Icons.queue_music,
          iconColor: Color(0xFF3B82F6),
          title: 'Features',
          subtitle:
              'Local files · YouTube search & streaming · Mixed queue · Auto-advance',
        ),
        const Gap(6),
        const _SettingsItem(
          icon: Icons.person_outline,
          iconColor: Colors.white38,
          title: 'Developer',
          subtitle: 'Mark Keshian M. Mangabay',
        ),
        const Gap(6),
        const _SettingsItem(
          icon: Icons.devices,
          iconColor: Colors.white38,
          title: 'Platform',
          subtitle: 'Android · macOS · Windows',
        ),
        const Gap(6),
        const _SettingsItem(
          icon: Icons.copyright,
          iconColor: Colors.white38,
          title: 'License',
          subtitle: '© 2026 Karaoke-Chan. All rights reserved.',
        ),
      ],
    );
  }

  void _confirmRestart(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title:
            const Text('Restart App?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will clear all queue entries, remove the saved folder, and return you to folder selection.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(libraryProvider.notifier).resetToStart();
            },
            child: const Text('Restart',
                style: TextStyle(
                    color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmClearQueue(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title:
            const Text('Clear Queue?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove all entries from the queue.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(queueNotifierProvider.notifier).clearAll();
            },
            child:
                const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _SettingsItem extends StatefulWidget {
  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  State<_SettingsItem> createState() => _SettingsItemState();
}

class _SettingsItemState extends State<_SettingsItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null ? _cardHover : _cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(widget.icon, color: widget.iconColor, size: 18),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Gap(2),
                  Text(widget.subtitle,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (widget.onTap != null)
              const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ]),
        ),
      ),
    );
  }
}

// ── Search mode toggle ────────────────────────────────────────────────────────

class _SearchModeToggle extends StatelessWidget {
  const _SearchModeToggle({required this.mode, required this.onChanged});
  final SearchMode mode;
  final void Function(SearchMode) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        _ToggleBtn(
          label: '🟢  Local',
          active: mode == SearchMode.local,
          activeColor: const Color(0xFF22C55E),
          onTap: () => onChanged(SearchMode.local),
        ),
        _ToggleBtn(
          label: '🔵  Online',
          active: mode == SearchMode.online,
          activeColor: const Color(0xFF3B82F6),
          onTap: () => onChanged(SearchMode.online),
        ),
      ]),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: activeColor, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? activeColor : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Online results list ───────────────────────────────────────────────────────

class _OnlineResultsList extends ConsumerWidget {
  const _OnlineResultsList({required this.onPlay});
  final void Function(YoutubeVideoResult) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ytState = ref.watch(youtubeSearchProvider);

    if (ytState.isIdle) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, color: Color(0xFF3B82F6), size: 36),
                Gap(10),
                Text('Online Search',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Gap(6),
                Text(
                  'Type a song name above to search YouTube.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (ytState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
      );
    }

    if (ytState.status == YoutubeSearchStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: Colors.redAccent, size: 32),
                const Gap(10),
                const Text('Search failed',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const Gap(6),
                Text(ytState.errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    if (ytState.isEmpty) {
      return const Center(
        child:
            Text('No results found', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 64),
      itemCount: ytState.results.length,
      itemBuilder: (_, i) => _YoutubeResultItem(
        video: ytState.results[i],
        onPlay: () => onPlay(ytState.results[i]),
      ),
    );
  }
}

class _YoutubeResultItem extends ConsumerStatefulWidget {
  const _YoutubeResultItem({required this.video, required this.onPlay});
  final YoutubeVideoResult video;
  final VoidCallback onPlay;

  @override
  ConsumerState<_YoutubeResultItem> createState() => _YoutubeResultItemState();
}

class _YoutubeResultItemState extends ConsumerState<_YoutubeResultItem> {
  bool _hovered = false;

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final unifiedQueue =
        ref.watch(playerProvider).valueOrNull?.unifiedQueue ?? const [];
    final isQueued = unifiedQueue.any(
        (i) => i.isYoutube && i.youtubeVideo?.videoId == widget.video.videoId);

    const blueQueue = Color(0xFF3B82F6);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _hovered ? _cardHover : _cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          // ── Info ─────────────────────────────────────────────────────
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                widget.video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const Gap(4),
              Text(
                widget.video.channel.isNotEmpty
                    ? 'Channel: ${widget.video.channel}'
                    : widget.video.duration != null
                        ? _formatDuration(widget.video.duration)
                        : 'YouTube',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _sub, fontSize: 13),
              ),
            ]),
          ),
          const Gap(8),
          // ── Queue button ─────────────────────────────────────────────
          isQueued
              ? const Tooltip(
                  message: 'Already queued',
                  child: Icon(Icons.check_circle,
                      color: Color(0xFF3B82F6), size: 22),
                )
              : ElevatedButton.icon(
                  onPressed: widget.onPlay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blueQueue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('QUEUE'),
                ),
        ]),
      ),
    );
  }
}

class _SongItem extends StatefulWidget {
  const _SongItem({
    required this.song,
    required this.isCurrent,
    required this.isQueued,
    required this.onQueue,
  });
  final Song song;
  final bool isCurrent;
  final bool isQueued;
  final VoidCallback onQueue;

  @override
  State<_SongItem> createState() => _SongItemState();
}

class _SongItemState extends State<_SongItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: widget.isCurrent
              ? const Color(0xFF1E3A5F)
              : (_hovered ? _cardHover : _cardBg),
          borderRadius: BorderRadius.circular(14),
          border:
              widget.isCurrent ? Border.all(color: _purple, width: 1.5) : null,
        ),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (widget.isCurrent)
                  const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.graphic_eq, color: _purple, size: 15)),
                Expanded(
                  child: Text(widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: widget.isCurrent ? _purple : Colors.white)),
                ),
              ]),
              const Gap(4),
              Text(
                widget.song.artist != null
                    ? 'Artist: ${widget.song.artist}'
                    : 'Folder: ${widget.song.folderName ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _sub, fontSize: 13),
              ),
            ]),
          ),
          const Gap(8),
          widget.isQueued
              ? const Tooltip(
                  message: 'Already queued',
                  child: Icon(Icons.check_circle, color: _queueGreen, size: 22),
                )
              : ElevatedButton.icon(
                  onPressed: widget.onQueue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _queueGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('QUEUE'),
                ),
        ]),
      ),
    );
  }
}

// ── Video area ───────────────────────────────────────────────────────────────

class _VideoArea extends ConsumerStatefulWidget {
  const _VideoArea({
    required this.player,
    required this.queue,
    required this.fullscreen,
    required this.onToggle,
  });
  final KaraokePlayerState player;
  final List<QueueEntry> queue;
  final bool fullscreen;
  final VoidCallback onToggle;

  @override
  ConsumerState<_VideoArea> createState() => _VideoAreaState();
}

class _VideoAreaState extends ConsumerState<_VideoArea> {
  bool _overlayVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Start the hide timer immediately so the overlay fades out on first load
    // even if the cursor never enters.
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _onCursorActivity() {
    debugPrint(
        '[Fullscreen] _onCursorActivity: overlayVisible=$_overlayVisible');
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(playerProvider.notifier);
    final controller = notifier.videoController;
    final player = widget.player;
    final queue = widget.queue;

    // Listener works at a lower level than MouseRegion and receives pointer
    // events even when a platform view (Video) is present underneath.
    // On Android, the Video platform view absorbs touch events, so we add an
    // explicit transparent GestureDetector overlay for Android.
    return Listener(
      onPointerHover: (_) => _onCursorActivity(),
      onPointerDown: (_) => _onCursorActivity(),
      child: MouseRegion(
        cursor: _overlayVisible
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        child: Container(
          color: Colors.black,
          child: Stack(children: [
            // Video widget — PERMANENTLY in the tree.
            if (controller != null)
              Positioned.fill(
                child: Video(
                  controller: controller,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
              ),

            // Idle placeholder
            if (player.isIdle)
              const Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.queue_music_rounded,
                          size: 64, color: Colors.white12),
                      Gap(20),
                      Text(
                        'No song selected',
                        style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 22,
                            fontWeight: FontWeight.w600),
                      ),
                      Gap(8),
                      Text(
                        'Pick a song from the list and tap QUEUE to start',
                        style:
                            TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

            // Audio-only indicator
            if (!player.isIdle &&
                !player.isLoading &&
                !player.hasVideo &&
                !player.hasError)
              const Center(
                child: Text(
                  '♫  Playing Audio',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 22),
                ),
              ),

            // Loading indicator (YouTube stream resolving / file opening)
            if (player.isLoading)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFF3B82F6),
                      strokeWidth: 3,
                    ),
                    const Gap(16),
                    Text(
                      player.currentEntry?.song?.title ?? 'Loading…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                    const Gap(6),
                    const Text(
                      'Preparing stream…',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Error display
            if (player.hasError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '⚠ ${player.errorMessage ?? "Playback error"}',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // On Android, the Video platform view absorbs all touch events so
            // the top-level Listener never fires for taps on the video itself.
            // Use a Positioned.fill transparent overlay to keep cursor-activity
            // detection working.  When the overlay is hidden we use an opaque
            // GestureDetector (first tap = show controls only, handled below in
            // the fullscreen-button logic).  When visible we use a Listener so
            // we don't enter the gesture arena and block child tap recognizers.
            if (Platform.isAndroid)
              Positioned.fill(
                child: _overlayVisible
                    ? Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => _onCursorActivity(),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onCursorActivity,
                      ),
              ),

            // ── Now-playing bar (bottom) ──────────────────────────────
            // Positioned directly in the Stack so it always fills the full
            // width.  IgnorePointer + AnimatedOpacity are applied INSIDE the
            // Positioned child so they never become invalid ParentDataWidgets.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_overlayVisible,
                child: AnimatedOpacity(
                  opacity: _overlayVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: _NowPlayingOverlay(player: player, queue: queue),
                ),
              ),
            ),

            // ── Fullscreen toggle (top-right) ─────────────────────────
            // Lives as its own Positioned in the Stack, completely separate
            // from IgnorePointer, so it is always hittable.  On first tap when
            // controls are hidden, show controls; on subsequent tap, toggle.
            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  debugPrint(
                      '[Fullscreen] button tapped: fullscreen=${widget.fullscreen}, overlayVisible=$_overlayVisible');
                  if (!_overlayVisible) {
                    _onCursorActivity();
                  } else {
                    widget.onToggle();
                  }
                },
                child: AnimatedOpacity(
                  opacity: _overlayVisible ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                        color: _overlayBg, shape: BoxShape.circle),
                    child: Icon(
                      widget.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NowPlayingOverlay extends ConsumerWidget {
  const _NowPlayingOverlay({required this.player, required this.queue});
  final KaraokePlayerState player;
  final List<QueueEntry> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (player.isIdle && queue.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(playerProvider.notifier);
    final song = player.currentEntry?.song;
    final next =
        queue.where((e) => e.status == QueueStatus.waiting).firstOrNull;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xDD000000)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 32, 24, MediaQuery.paddingOf(context).bottom + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Now Playing | Controls | Up Next (single row) ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // NOW PLAYING (left)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('NOW PLAYING',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                            letterSpacing: 1.5)),
                    const Gap(4),
                    Text(
                      song?.title ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    if ((song?.artist ?? song?.folderName) != null)
                      Text(
                        song!.artist ?? song.folderName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _sub, fontSize: 13),
                      ),
                  ],
                ),
              ),
              // Controls (center)
              if (song != null) ...[
                const Gap(24),
                GestureDetector(
                  onTap: notifier.togglePlayPause,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                        color: _purple, shape: BoxShape.circle),
                    child: Icon(
                        player.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 26),
                  ),
                ),
                const Gap(16),
                GestureDetector(
                  onTap: notifier.skip,
                  child: const Icon(Icons.skip_next,
                      color: Colors.white70, size: 32),
                ),
                const Gap(24),
              ],
              // UP NEXT (right)
              Expanded(
                child: next != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('UP NEXT',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white38,
                                  letterSpacing: 1.5)),
                          const Gap(4),
                          Text(
                            next.song?.title ?? 'Song #${next.songId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          if (next.song?.artist != null ||
                              next.song?.folderName != null)
                            Text(
                              next.song!.artist ?? next.song!.folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _sub, fontSize: 13),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),

          // ── Seek bar ──────────────────────────────────────────────
          if (song != null) ...[
            const Gap(12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: _purple,
                inactiveTrackColor: Colors.white24,
                thumbColor: _purple,
              ),
              child: Slider(
                value: player.progressFraction,
                onChanged: (v) {
                  if (player.duration > Duration.zero) {
                    notifier.seek(player.duration * v);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(player.position),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(_fmt(player.duration),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            const Gap(8),
            // ── Volume ──────────────────────────────────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => notifier.toggleMute(),
                  child: Icon(
                    player.volume == 0
                        ? Icons.volume_off
                        : player.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color:
                        player.volume == 0 ? Colors.redAccent : Colors.white54,
                    size: 18,
                  ),
                ),
                const Gap(4),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 8),
                      activeTrackColor: Colors.white70,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: player.volume.clamp(0.0, 1.0),
                      onChanged: (v) => notifier.setVolume(v),
                    ),
                  ),
                ),
                const Gap(4),
                Text(
                  '${(player.volume * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Queue panel ──────────────────────────────────────────────────────────────

class _QueuePanel extends ConsumerWidget {
  const _QueuePanel({required this.queue, required this.height});
  final List<QueueEntry> queue;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unifiedQueue =
        ref.watch(playerProvider).valueOrNull?.unifiedQueue ?? const [];
    final totalCount = unifiedQueue.length;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: _sidebarBg,
          border: Border(top: BorderSide(color: _border, width: 2)),
        ),
        padding: const EdgeInsets.all(20),
        child: ClipRect(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Queue List',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (totalCount > 0) ...[
                const Gap(10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$totalCount',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            const Gap(12),
            Expanded(
              child: totalCount == 0
                  ? const Center(
                      child: Text('Queue is empty',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: unifiedQueue.length,
                      itemBuilder: (_, i) {
                        final item = unifiedQueue[i];
                        return _QueueItem(
                          label: item.title,
                          position: i + 1,
                          isYoutube: item.isYoutube,
                          onRemove: () => ref
                              .read(playerProvider.notifier)
                              .removeQueueItemAt(i),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.label,
    required this.position,
    required this.isYoutube,
    required this.onRemove,
  });
  final String label;
  final int position;
  final bool isYoutube;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _cardBg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        // ── Source badge ────────────────────────────────────────────
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: isYoutube
                ? const Color(0xFF1D4ED8).withValues(alpha: 0.3)
                : _queueGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            isYoutube ? Icons.language : Icons.music_note,
            size: 13,
            color: isYoutube ? const Color(0xFF60A5FA) : _queueGreen,
          ),
        ),
        // ── Position ────────────────────────────────────────────────
        Text('$position. ',
            style: const TextStyle(color: Colors.white38, fontSize: 13)),
        // ── Title ───────────────────────────────────────────────────
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14)),
        ),
        const Gap(8),
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: Colors.white38, size: 16),
          ),
      ]),
    );
  }
}
