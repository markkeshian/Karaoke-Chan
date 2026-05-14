// lib/features/home/presentation/karaoke_stage.dart
// Main screen: sidebar (search + song list) + video area + queue panel.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';
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

// ── Design tokens ────────────────────────────────────────────────────────────
const _bg = Color(0xFF111827);
const _sidebarBg = Color(0xFF1F2937);
const _border = Color(0xFF374151);
const _cardBg = Color(0xFF374151);
const _cardHover = Color(0xFF4B5563);
const _queueGreen = Color(0xFF22C55E);
const _sub = Color(0xFFCBD5E1);
const _overlayBg = Color(0xB3000000);
const _purple = Color(0xFFE040FB);

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
  bool _showSettings = false;
  double? _sidebarWidth;
  double _queueHeight = 220;
  SearchMode _searchMode = SearchMode.local;
  bool _karaokeMode = true;
  Timer? _ytDebounce;

  // Narrow-layout tab: 0 = Songs, 1 = Now Playing / Queue
  int _activeTab = 0;

  // Breakpoint: below this width the layout switches to stacked (phone) mode.
  static const double _narrowBreak = 600;

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

          return LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _narrowBreak;

            // ── NARROW (phone): stacked tab layout ────────────────────
            if (isNarrow && !_fullscreen) {
              return Column(
                children: [
                  // Tab bar at the top
                  _NarrowTabBar(
                    activeTab: _activeTab,
                    onTab: (i) => setState(() => _activeTab = i),
                    isPlaying: !player.isIdle,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        // ── Tab 0: Song search ───────────────────────
                        _Sidebar(
                          library: library,
                          searchCtrl: _search,
                          searchFocusNode: _searchFocusNode,
                          sidebarWidth: constraints.maxWidth,
                          currentSongId: player.currentEntry?.songId,
                          queuedSongIds: queue
                              .where((e) =>
                                  e.status == QueueStatus.waiting ||
                                  e.status == QueueStatus.playing)
                              .map((e) => e.songId)
                              .toSet(),
                          onQueue: (s) {
                            _queueSong(s, player);
                            // Jump to player tab so user sees it queued
                            setState(() => _activeTab = 1);
                          },
                          onChangeFolder: () =>
                              ref.read(libraryProvider.notifier).changeFolder(),
                          searchMode: _searchMode,
                          karaokeMode: _karaokeMode,
                          onKaraokeModeChanged: (val) =>
                              _onKaraokeModeChanged(val),
                          onSearchModeChanged: (mode) =>
                              _onSearchModeChanged(mode),
                          onYoutubeSearch: (q) => _onYoutubeSearch(q),
                          onYoutubePlay: (video) {
                            _queueYoutube(video, player);
                            setState(() => _activeTab = 1);
                          },
                          showSettings: _showSettings,
                          onToggleSettings: () =>
                              setState(() => _showSettings = !_showSettings),
                        ),
                        // ── Tab 1: Player + Queue ────────────────────
                        Column(
                          children: [
                            Expanded(
                              child: _VideoArea(
                                player: player,
                                queue: queue,
                                fullscreen: false,
                                onToggle: () => _toggleFullscreen(),
                              ),
                            ),
                            const _PlayerControlBar(),
                            _QueuePanel(
                              queue: queue,
                              height: (constraints.maxHeight * 0.35)
                                  .clamp(160.0, 320.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // ── WIDE (tablet / desktop): side-by-side layout ──────────
            final defaultSidebarW =
                (constraints.maxWidth * 0.32).clamp(260.0, 420.0);
            final sidebarW =
                _sidebarWidth?.clamp(260.0, constraints.maxWidth * 0.50) ??
                    defaultSidebarW;
            final queueH = _queueHeight.clamp(160.0,
                (constraints.maxHeight * 0.55).clamp(160.0, double.infinity));

            return Row(
              children: [
                if (!_fullscreen) ...[
                  _Sidebar(
                    library: library,
                    searchCtrl: _search,
                    searchFocusNode: _searchFocusNode,
                    sidebarWidth: sidebarW,
                    currentSongId: player.currentEntry?.songId,
                    queuedSongIds: queue
                        .where((e) =>
                            e.status == QueueStatus.waiting ||
                            e.status == QueueStatus.playing)
                        .map((e) => e.songId)
                        .toSet(),
                    onQueue: (s) => _queueSong(s, player),
                    onChangeFolder: () =>
                        ref.read(libraryProvider.notifier).changeFolder(),
                    searchMode: _searchMode,
                    karaokeMode: _karaokeMode,
                    onKaraokeModeChanged: (val) => _onKaraokeModeChanged(val),
                    onSearchModeChanged: (mode) => _onSearchModeChanged(mode),
                    onYoutubeSearch: (q) => _onYoutubeSearch(q),
                    onYoutubePlay: (video) => _queueYoutube(video, player),
                    showSettings: _showSettings,
                    onToggleSettings: () =>
                        setState(() => _showSettings = !_showSettings),
                  ),
                  // ── Sidebar drag resizer ────────────────────────────
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        final screenW = constraints.maxWidth;
                        setState(() {
                          _sidebarWidth = ((sidebarW) + d.delta.dx)
                              .clamp(260.0, screenW * 0.50);
                        });
                      },
                      child: Container(
                        width: 6,
                        color: _border,
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
                        const _PlayerControlBar(),
                        // ── Queue panel drag resizer ──────────────────
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: GestureDetector(
                            onVerticalDragUpdate: (d) {
                              setState(() {
                                _queueHeight = (_queueHeight - d.delta.dy)
                                    .clamp(
                                        160.0,
                                        (constraints.maxHeight * 0.55)
                                            .clamp(160.0, double.infinity));
                              });
                            },
                            child: Container(
                              height: 16,
                              color: const Color(0xFF111827),
                              child: Center(
                                child: Container(
                                  width: 48,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _QueuePanel(queue: queue, height: queueH),
                      ],
                    ],
                  ),
                ),
              ],
            );
          });
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

  void _onKaraokeModeChanged(bool val) {
    setState(() {
      _karaokeMode = val;
      final q = _search.text;
      if (_searchMode == SearchMode.online && q.isNotEmpty) {
        _ytDebounce?.cancel();
        final effectiveQ = val ? '$q karaoke' : q;
        ref.read(youtubeSearchProvider.notifier).search(effectiveQ);
      }
    });
  }

  void _onSearchModeChanged(SearchMode mode) {
    setState(() {
      _searchMode = mode;
      _ytDebounce?.cancel();
      final q = _search.text;
      if (mode == SearchMode.local) {
        ref.read(youtubeSearchProvider.notifier).clear();
        ref.read(libraryProvider.notifier).search(q);
      } else {
        ref.read(libraryProvider.notifier).search('');
        if (q.isNotEmpty) {
          final effectiveQ = _karaokeMode ? '$q karaoke' : q;
          ref.read(youtubeSearchProvider.notifier).search(effectiveQ);
        } else {
          ref.read(youtubeSearchProvider.notifier).clear();
        }
      }
    });
  }

  void _onYoutubeSearch(String q) {
    _ytDebounce?.cancel();
    _ytDebounce = Timer(const Duration(milliseconds: 600), () {
      final effectiveQ = _karaokeMode ? '$q karaoke' : q;
      ref.read(youtubeSearchProvider.notifier).search(effectiveQ);
    });
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

  bool get _isPermissionError =>
      message.toLowerCase().contains('permission') ||
      message.toLowerCase().contains('denied') ||
      message.toLowerCase().contains('no files found');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPerm = _isPermissionError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isPerm ? Icons.folder_off_outlined : Icons.warning_amber_rounded,
            color: isPerm ? Colors.orangeAccent : Colors.redAccent,
            size: 52,
          ),
          const Gap(20),
          Text(
            isPerm ? 'No Access to Folder' : 'Scan Failed',
            style: TextStyle(
                color: isPerm ? Colors.orangeAccent : Colors.redAccent,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const Gap(12),
          Text(
            isPerm
                ? 'Karaoke-Chan couldn\'t read the selected folder.\nThis usually means storage permission was denied or the folder is empty.'
                : message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _sub, fontSize: 14, height: 1.6),
          ),
          if (isPerm) ...[
            const Gap(8),
            const Text(
              'Go to App Settings → Permissions → Files and Media → Allow.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white38, fontSize: 12, height: 1.6),
            ),
          ],
          const Gap(32),
          if (isPerm)
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open App Settings',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          const Gap(12),
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
    required this.karaokeMode,
    required this.onKaraokeModeChanged,
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
  final bool karaokeMode;
  final void Function(bool) onKaraokeModeChanged;
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
                            suffixIcon: searchMode == SearchMode.online
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (value.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.clear,
                                              color: Colors.white38, size: 18),
                                          onPressed: () {
                                            searchCtrl.clear();
                                            ref
                                                .read(libraryProvider.notifier)
                                                .search('');
                                          },
                                        ),
                                      Tooltip(
                                        message: karaokeMode
                                            ? 'Karaoke mode ON — tap to disable'
                                            : 'Karaoke mode OFF — tap to enable',
                                        child: GestureDetector(
                                          onTap: () => onKaraokeModeChanged(
                                              !karaokeMode),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: Icon(
                                                Icons.mic,
                                                key: ValueKey(karaokeMode),
                                                size: 20,
                                                color: karaokeMode
                                                    ? const Color(0xFFE040FB)
                                                    : Colors.white24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : value.text.isNotEmpty
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
                    : !library.hasFolder
                        ? _NoFolderPrompt(onPick: onChangeFolder)
                        : library.songs.isEmpty
                            ? const Center(
                                child: Text('No songs found',
                                    style: TextStyle(color: Colors.white38)))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(15, 15, 15, 64),
                                itemCount: library.songs.length,
                                itemBuilder: (_, i) => _SongItem(
                                  song: library.songs[i],
                                  isCurrent:
                                      library.songs[i].id == currentSongId,
                                  isQueued: library.songs[i].id != null &&
                                      queuedSongIds
                                          .contains(library.songs[i].id),
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

        // ── Danger zone ──────────────────────────────────────────────────
        const _SettingsSectionLabel(label: 'Danger Zone'),
        const Gap(8),
        _SettingsItem(
          icon: Icons.delete_sweep_outlined,
          iconColor: Colors.redAccent,
          title: 'Clear All Data',
          subtitle: 'Remove all songs, queue entries, and saved folder',
          onTap: () => _confirmClearAll(context, ref),
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
              'Local files · YouTube search & streaming · Mixed queue · Auto-advance · Fullscreen mode',
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
          title: 'Platforms',
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

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Clear All Data?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will stop playback, clear the queue, remove all scanned songs, and forget the saved folder. This cannot be undone.',
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
            child: const Text('Clear All',
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
      height: 38,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        _ToggleBtn(
          icon: Icons.music_note,
          label: 'Local',
          active: mode == SearchMode.local,
          activeColor: const Color(0xFF22C55E),
          onTap: () => onChanged(SearchMode.local),
        ),
        _ToggleBtn(
          icon: Icons.language,
          label: 'Online',
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
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });
  final IconData icon;
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 13, color: active ? activeColor : Colors.white38),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? activeColor : Colors.white38,
                ),
              ),
            ],
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
                    ? [
                        widget.video.channel,
                        if (widget.video.duration != null)
                          _formatDuration(widget.video.duration),
                      ].join(' · ')
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
                        horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    minimumSize: const Size(80, 40),
                  ),
                  icon: const Icon(Icons.add, size: 16),
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
              Row(
                children: [
                  Icon(
                    widget.song.artist != null
                        ? Icons.person_outline
                        : Icons.folder_outlined,
                    color: Colors.white38,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.song.artist ?? widget.song.folderName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _sub, fontSize: 13),
                    ),
                  ),
                ],
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
                        horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    minimumSize: const Size(80, 40),
                  ),
                  icon: const Icon(Icons.add, size: 16),
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
    // Start hide timer on load so overlay fades out without needing cursor movement.
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_VideoArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always re-show the overlay when the user switches into fullscreen
    // so controls are immediately visible and readable.
    if (widget.fullscreen && !oldWidget.fullscreen) {
      setState(() => _overlayVisible = true);
      _startHideTimer();
    }
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

    // Use Listener for broad pointer coverage; Android needs overlay for touch on the video platform view.
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

            // Android: transparent overlay to capture touch events absorbed by the video platform view.
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

            // Now-playing bar at the bottom of the video area — fullscreen only.
            // In normal mode, _PlayerControlBar (below the video) is always visible.
            if (widget.fullscreen)
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

            // Fullscreen toggle button (top-right); first tap shows controls, second toggles.
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
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xF0000000)],
          stops: [0.0, 0.45],
        ),
      ),
      padding: EdgeInsets.fromLTRB(28, 48, 28, bottomPad + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Seek bar (full width, time flanking the slider) ────────
          if (song != null) ...[
            Row(
              children: [
                Text(_fmt(player.position),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
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
                ),
                Text(_fmt(player.duration),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // ── Main row: Now Playing | Controls | Up Next ─────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Left: NOW PLAYING ────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('NOW PLAYING',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(
                      song?.title ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.2),
                    ),
                    if ((song?.artist ?? song?.folderName) != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            song!.artist != null
                                ? Icons.person_outline
                                : Icons.folder_outlined,
                            color: Colors.white38,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              song.artist ?? song.folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _sub, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // ── Center: Play/Pause + Next ──────────────────────
              if (song != null) ...[
                const SizedBox(width: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _MediaButton(
                      onTap: notifier.togglePlayPause,
                      size: 60,
                      backgroundColor: _purple,
                      borderColor: Colors.transparent,
                      icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
                      iconColor: Colors.black,
                      iconSize: 32,
                      label: player.isPlaying ? 'PAUSE' : 'PLAY',
                      labelColor: _purple.withOpacity(0.85),
                    ),
                    const SizedBox(width: 20),
                    _MediaButton(
                      onTap: notifier.skip,
                      size: 48,
                      backgroundColor: Colors.white.withOpacity(0.10),
                      borderColor: Colors.white38,
                      icon: Icons.skip_next,
                      iconColor: Colors.white,
                      iconSize: 24,
                      label: 'NEXT',
                      labelColor: Colors.white38,
                      tooltip: 'Skip to next song',
                    ),
                  ],
                ),
                const SizedBox(width: 24),
              ],
              // ── Right: UP NEXT ───────────────────────────────────
              Expanded(
                child: next != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('UP NEXT',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white38,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 4),
                          Text(
                            next.song?.title ?? 'Song #${next.songId}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                height: 1.2),
                          ),
                          if (next.song?.artist != null ||
                              next.song?.folderName != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              next.song!.artist ?? next.song!.folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: _sub, fontSize: 13),
                            ),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          // ── Volume row ────────────────────────────────────────────
          if (song != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: notifier.toggleMute,
                  child: Icon(
                    player.volume == 0
                        ? Icons.volume_off
                        : player.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color:
                        player.volume == 0 ? Colors.redAccent : Colors.white54,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 130,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
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
                const SizedBox(width: 6),
                Text(
                  '${(player.volume * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── Always-visible player control bar (normal / non-fullscreen view) ─────────

class _PlayerControlBar extends ConsumerWidget {
  const _PlayerControlBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(playerProvider);
    final player = playerAsync.valueOrNull;
    if (player == null || player.isIdle) return const SizedBox.shrink();

    final notifier = ref.read(playerProvider.notifier);
    final song = player.currentEntry?.song;

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 420;

      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A2235),
          border: Border(
            top: BorderSide(color: _border, width: 1),
            bottom: BorderSide(color: _border, width: 1),
          ),
        ),
        padding:
            EdgeInsets.fromLTRB(isNarrow ? 12 : 20, 8, isNarrow ? 12 : 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Progress bar row ─────────────────────────────────────
            Row(
              children: [
                Text(
                  _fmt(player.position),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
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
                ),
                Text(
                  _fmt(player.duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),

            if (isNarrow) ...[
              // ── NARROW: single row — vol-icon | song info | play | next ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Mute toggle icon (replaces full slider on narrow)
                  GestureDetector(
                    onTap: () => notifier.toggleMute(),
                    child: Icon(
                      player.volume == 0
                          ? Icons.volume_off
                          : player.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      color: player.volume == 0
                          ? Colors.redAccent
                          : Colors.white54,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Song title (flexible)
                  Expanded(
                    child: Text(
                      song?.title ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Play / Pause
                  GestureDetector(
                    onTap: notifier.togglePlayPause,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        player.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Next
                  GestureDetector(
                    onTap: notifier.skip,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // ── WIDE: 3-column — song info | controls | volume ────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: Song title + artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song?.title ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if ((song?.artist ?? song?.folderName) != null)
                          Text(
                            song!.artist ?? song.folderName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _sub, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  // Center: Play/Pause + Next
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _MediaButton(
                        onTap: notifier.togglePlayPause,
                        size: 54,
                        backgroundColor: _purple,
                        borderColor: Colors.transparent,
                        icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
                        iconColor: Colors.black,
                        iconSize: 28,
                        label: player.isPlaying ? 'PAUSE' : 'PLAY',
                        labelColor: _purple.withOpacity(0.8),
                      ),
                      const SizedBox(width: 18),
                      _MediaButton(
                        onTap: notifier.skip,
                        size: 44,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        borderColor: Colors.white38,
                        icon: Icons.skip_next,
                        iconColor: Colors.white,
                        iconSize: 22,
                        label: 'NEXT',
                        labelColor: Colors.white38,
                        tooltip: 'Skip to next song',
                      ),
                    ],
                  ),
                  // Right: Volume slider
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => notifier.toggleMute(),
                          child: Icon(
                            player.volume == 0
                                ? Icons.volume_off
                                : player.volume < 0.5
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                            color: player.volume == 0
                                ? Colors.redAccent
                                : Colors.white54,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                minWidth: 40, maxWidth: 120),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 8),
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
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(player.volume * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// A single circular media button with an icon and a small text label below.
/// Both play and next use this widget so they always have the same structure
/// and height — guaranteeing perfect vertical alignment in their parent Row.
class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.onTap,
    required this.size,
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.iconSize,
    required this.label,
    required this.labelColor,
    this.tooltip,
  });

  final VoidCallback onTap;
  final double size;
  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String label;
  final Color labelColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tooltip != null ? Tooltip(message: tooltip!, child: button) : button,
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ── No-folder inline prompt (shown in sidebar when no folder is set) ─────────

class _NoFolderPrompt extends StatelessWidget {
  const _NoFolderPrompt({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _queueGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_outlined,
                  color: _queueGreen, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'No local songs yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap below to choose the folder where your karaoke files are saved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _queueGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Choose Folder'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You can still search & play songs online while you decide.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white24, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
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
        padding: EdgeInsets.all(height < 160 ? 10 : 20),
        child: ClipRect(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.queue_music_rounded,
                  color: Colors.white54, size: 20),
              const SizedBox(width: 8),
              const Text('Up Next',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (totalCount > 0) ...[
                const Gap(10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: _purple.withOpacity(0.4), width: 1),
                  ),
                  child: Text('$totalCount',
                      style: const TextStyle(
                          color: _purple,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            const Gap(12),
            Expanded(
              child: totalCount == 0
                  ? Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.queue_music_rounded,
                                size: 36, color: Colors.white12),
                            const SizedBox(height: 10),
                            const Text('Queue is empty',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            const Text('Add songs from the list on the left',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
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
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 16),
            ),
          ),
      ]),
    );
  }
}

// ── Narrow layout tab bar ──────────────────────────────────────────────────────
class _NarrowTabBar extends StatelessWidget {
  const _NarrowTabBar({
    required this.activeTab,
    required this.onTab,
    required this.isPlaying,
  });

  final int activeTab;
  final ValueChanged<int> onTab;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _sidebarBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Tab(
                label: 'Songs',
                icon: Icons.library_music_outlined,
                selected: activeTab == 0,
                onTap: () => onTab(0),
              ),
              _Tab(
                label: 'Now Playing',
                icon: isPlaying
                    ? Icons.play_circle_filled
                    : Icons.play_circle_outline,
                selected: activeTab == 1,
                onTap: () => onTab(1),
              ),
            ],
          ),
          const Divider(height: 1, thickness: 1, color: _border),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const inactive = Color(0xFF9CA3AF);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: selected ? _purple : inactive),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _purple : inactive,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: selected ? 32 : 0,
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
