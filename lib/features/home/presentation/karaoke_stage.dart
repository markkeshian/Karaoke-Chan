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
// Lightened from 0xFF374151 → better contrast against sidebarBg (~2.4:1 → ~3.2:1)
const _cardBg = Color(0xFF3D4F65);
const _cardHover = Color(0xFF4B5F78);
const _queueGreen = Color(0xFF22C55E);
const _sub = Color(0xFFCBD5E1);
const _overlayBg = Color(0xB3000000);
const _purple = Color(0xFFE040FB);
const _blue = Color(0xFF3B82F6);

// ── Spacing scale (4-pt grid) ─────────────────────────────────────────────────
const _sp4 = 4.0;
const _sp8 = 8.0;
const _sp12 = 12.0;
const _sp16 = 16.0;
const _sp20 = 20.0;
const _sp24 = 24.0;

// ── Type scale ────────────────────────────────────────────────────────────────
const _tsXs = 11.0; // overlines, badges, tiny labels (was 9/10)
const _tsSm = 12.0; // secondary/meta text
const _tsBase = 14.0; // body text
const _tsMd = 16.0; // list titles
const _tsLg = 20.0; // section headings
const _tsXl = 22.0; // page headings

// ── Minimum touch target (WCAG / Apple HIG / Material) ───────────────────────
const _kMinTarget = 44.0;

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

            // ── NARROW (phone): video-first layout ───────────────────
            if (isNarrow && !_fullscreen) {
              final queueWaiting =
                  queue.where((e) => e.status == QueueStatus.waiting).length;
              return Column(
                children: [
                  // ── Video always visible at top, full width 16:9 ──────
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _VideoArea(
                      player: player,
                      queue: queue,
                      fullscreen: false,
                      onToggle: () => _toggleFullscreen(),
                    ),
                  ),
                  // ── Slim control bar (only when song is playing) ───────
                  if (!player.isIdle) const _PlayerControlBar(compact: true),
                  // ── Pill tab chips ─────────────────────────────────────
                  _PhoneChipBar(
                    activeTab: _activeTab,
                    queueCount: queueWaiting,
                    onTab: (i) => setState(() => _activeTab = i),
                  ),
                  // ── Content: song list OR queue list ───────────────────
                  Expanded(
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
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
                        _PhoneQueueList(queue: queue),
                      ],
                    ),
                  ),
                ],
              );
            }

            // ── WIDE (tablet / desktop): side-by-side layout ──────────
            // On short screens (Android landscape) collapse controls + queue.
            final isShortScreen = constraints.maxHeight < 520;
            final defaultSidebarW =
                (constraints.maxWidth * 0.32).clamp(260.0, 420.0);
            final sidebarW =
                _sidebarWidth?.clamp(260.0, constraints.maxWidth * 0.50) ??
                    defaultSidebarW;
            final queueMinH = isShortScreen ? 100.0 : 160.0;
            final queueDefaultH = isShortScreen ? 130.0 : _queueHeight;
            final queueH = queueDefaultH.clamp(
                queueMinH,
                (constraints.maxHeight * 0.45)
                    .clamp(queueMinH, double.infinity));

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
                  _SidebarResizer(
                    onDragUpdate: (dx) {
                      final screenW = constraints.maxWidth;
                      setState(() {
                        _sidebarWidth =
                            (sidebarW + dx).clamp(260.0, screenW * 0.50);
                      });
                    },
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
                        _PlayerControlBar(compact: isShortScreen),
                        if (!isShortScreen)
                          _QueueResizer(
                            onDragUpdate: (dy) {
                              setState(() {
                                _queueHeight = (_queueHeight - dy).clamp(
                                    queueMinH,
                                    (constraints.maxHeight * 0.45)
                                        .clamp(queueMinH, double.infinity));
                              });
                            },
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
    }
  }

  void _queueYoutube(YoutubeVideoResult video, KaraokePlayerState player) {
    if (player.isIdle) {
      ref.read(playerProvider.notifier).playYoutube(video);
    } else {
      ref.read(playerProvider.notifier).queueYoutube(video);
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
        padding: const EdgeInsets.symmetric(horizontal: _sp20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.radar, color: _purple, size: 48),
          const Gap(20),
          const Text('Scanning Folder…',
              style: TextStyle(
                  color: _purple,
                  fontSize: _tsLg,
                  fontWeight: FontWeight.bold)),
          const Gap(8),
          Text('${library.scannedCount} songs found',
              style: const TextStyle(color: _sub, fontSize: _tsBase)),
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
        padding: const EdgeInsets.symmetric(horizontal: _sp24),
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
                fontSize: _tsXl,
                fontWeight: FontWeight.bold),
          ),
          const Gap(12),
          Text(
            isPerm
                ? 'Karaoke-Chan couldn\'t read the selected folder.\nThis usually means storage permission was denied or the folder is empty.'
                : message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _sub, fontSize: _tsBase, height: 1.6),
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
                                fontSize: _tsLg,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                      // Settings toggle — minimum 44×44 touch target
                      Semantics(
                        label:
                            showSettings ? 'Close Settings' : 'Open Settings',
                        button: true,
                        child: SizedBox(
                          width: _kMinTarget,
                          height: _kMinTarget,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              showSettings
                                  ? Icons.close
                                  : Icons.settings_outlined,
                              color: showSettings
                                  ? Colors.white70
                                  : Colors.white38,
                              size: 20,
                            ),
                            tooltip:
                                showSettings ? 'Close Settings' : 'Settings',
                            onPressed: onToggleSettings,
                          ),
                        ),
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
                                      Semantics(
                                        label: karaokeMode
                                            ? 'Karaoke mode ON — tap to disable'
                                            : 'Karaoke mode OFF — tap to enable',
                                        button: true,
                                        child: GestureDetector(
                                          onTap: () => onKaraokeModeChanged(
                                              !karaokeMode),
                                          child: SizedBox(
                                            width: _kMinTarget,
                                            height: _kMinTarget,
                                            child: Center(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                child: Icon(
                                                  Icons.mic,
                                                  key: ValueKey(karaokeMode),
                                                  size: 20,
                                                  color: karaokeMode
                                                      ? _purple
                                                      : Colors.white24,
                                                ),
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
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: showSettings
                    ? _SidebarSettingsPanel(
                        key: const ValueKey('settings'),
                        onChangeFolder: onChangeFolder,
                        onClose: onToggleSettings,
                      )
                    : _SidebarContent(
                        key: const ValueKey('songs'),
                        library: library,
                        searchMode: searchMode,
                        currentSongId: currentSongId,
                        queuedSongIds: queuedSongIds,
                        onQueue: onQueue,
                        onChangeFolder: onChangeFolder,
                        onYoutubePlay: onYoutubePlay,
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Sidebar content (song list / online results / empty state) ───────────────

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    super.key,
    required this.library,
    required this.searchMode,
    required this.currentSongId,
    required this.queuedSongIds,
    required this.onQueue,
    required this.onChangeFolder,
    required this.onYoutubePlay,
  });

  final LibraryState library;
  final SearchMode searchMode;
  final int? currentSongId;
  final Set<int> queuedSongIds;
  final void Function(Song) onQueue;
  final VoidCallback onChangeFolder;
  final void Function(YoutubeVideoResult) onYoutubePlay;

  @override
  Widget build(BuildContext context) {
    if (searchMode == SearchMode.online) {
      return _OnlineResultsList(onPlay: onYoutubePlay);
    }
    if (!library.hasFolder) {
      return _NoFolderPrompt(onPick: onChangeFolder);
    }
    if (library.songs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_outlined, color: Colors.white24, size: 36),
            SizedBox(height: 12),
            Text('No songs found',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: _tsBase,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
      itemCount: library.songs.length,
      itemBuilder: (_, i) => _SongItem(
        song: library.songs[i],
        isCurrent: library.songs[i].id == currentSongId,
        isQueued: library.songs[i].id != null &&
            queuedSongIds.contains(library.songs[i].id),
        onQueue: () => onQueue(library.songs[i]),
      ),
    );
  }
}

// ── Sidebar settings panel ───────────────────────────────────────────────────

class _SidebarSettingsPanel extends ConsumerWidget {
  const _SidebarSettingsPanel({
    super.key,
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
        fontSize: _tsXs,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: _cardBg,
        child: InkWell(
          onTap: onTap,
          hoverColor: _cardHover.withValues(alpha: 0.6),
          splashColor: Colors.white10,
          highlightColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, color: iconColor, size: 18),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: _tsBase,
                            fontWeight: FontWeight.w600)),
                    const Gap(2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: _tsSm),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    color: Colors.white24, size: 16),
            ]),
          ),
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
      height: 32,
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
                  size: 12, color: active ? activeColor : Colors.white38),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
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
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, color: _blue, size: 40),
                SizedBox(height: 12),
                Text('Online Search',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: _tsMd,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  'Type a song name above to search YouTube.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white38, fontSize: _tsSm, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (ytState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _blue),
      );
    }

    if (ytState.status == YoutubeSearchStatus.error) {
      final notifier = ref.read(youtubeSearchProvider.notifier);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: Colors.redAccent, size: 36),
                const SizedBox(height: 12),
                const Text('Search failed',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: _tsBase)),
                const SizedBox(height: 6),
                Text(ytState.errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: _tsSm)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => notifier.retryLast(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try Again',
                        style: TextStyle(
                            fontSize: _tsBase, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (ytState.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, color: Colors.white24, size: 36),
              SizedBox(height: 12),
              Text('No results found',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: _tsBase,
                      fontWeight: FontWeight.w500)),
              SizedBox(height: 6),
              Text(
                'Try a different search term',
                style: TextStyle(color: Colors.white24, fontSize: _tsSm),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
      itemCount: ytState.results.length,
      itemBuilder: (_, i) => _YoutubeResultItem(
        video: ytState.results[i],
        onPlay: () => onPlay(ytState.results[i]),
      ),
    );
  }
}

class _YoutubeResultItem extends ConsumerWidget {
  const _YoutubeResultItem({required this.video, required this.onPlay});
  final YoutubeVideoResult video;
  final VoidCallback onPlay;

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unifiedQueue =
        ref.watch(playerProvider).valueOrNull?.unifiedQueue ?? const [];
    final isQueued = unifiedQueue
        .any((i) => i.isYoutube && i.youtubeVideo?.videoId == video.videoId);

    return Container(
      margin: const EdgeInsets.only(bottom: _sp12),
      decoration: BoxDecoration(
        color: isQueued ? _blue.withValues(alpha: 0.08) : _cardBg,
        borderRadius: BorderRadius.circular(14),
        border:
            isQueued ? Border.all(color: _blue.withValues(alpha: 0.3)) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isQueued ? null : onPlay,
            hoverColor: _cardHover.withValues(alpha: 0.5),
            splashColor: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: _tsMd,
                              fontWeight: FontWeight.bold,
                              color: isQueued ? Colors.white70 : Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.channel.isNotEmpty
                              ? [
                                  video.channel,
                                  if (video.duration != null)
                                    _formatDuration(video.duration),
                                ].join(' · ')
                              : video.duration != null
                                  ? _formatDuration(video.duration)
                                  : 'YouTube',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _sub, fontSize: _tsSm),
                        ),
                      ]),
                ),
                const SizedBox(width: _sp8),
                isQueued
                    ? Semantics(
                        label: 'Already queued',
                        child: const Icon(Icons.check_circle,
                            color: _blue, size: 22),
                      )
                    : Semantics(
                        label: 'Add to queue',
                        button: true,
                        child: ElevatedButton.icon(
                          onPressed: onPlay,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: _tsSm),
                            minimumSize: const Size(_kMinTarget, _kMinTarget),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('QUEUE'),
                        ),
                      ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SongItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final Color rowBg = isCurrent
        ? const Color(0xFF1E3A5F)
        : isQueued
            ? _queueGreen.withValues(alpha: 0.07)
            : _cardBg;

    return Container(
      margin: const EdgeInsets.only(bottom: _sp8),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent ? Border.all(color: _purple, width: 1.5) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isQueued ? null : onQueue,
            hoverColor: _cardHover.withValues(alpha: 0.4),
            splashColor: Colors.white10,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: _sp12, vertical: _sp8),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (isCurrent)
                            const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.graphic_eq,
                                    color: _purple, size: 14)),
                          Expanded(
                            child: Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: _tsMd,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent
                                        ? _purple
                                        : isQueued
                                            ? Colors.white70
                                            : Colors.white)),
                          ),
                        ]),
                        const SizedBox(height: _sp4),
                        Row(
                          children: [
                            Icon(
                              song.artist != null
                                  ? Icons.person_outline
                                  : Icons.folder_outlined,
                              color: Colors.white38,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                song.artist ?? song.folderName ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _sub, fontSize: _tsSm),
                              ),
                            ),
                          ],
                        ),
                      ]),
                ),
                const SizedBox(width: _sp8),
                isQueued
                    ? Semantics(
                        label: 'Already queued',
                        child: const Icon(Icons.check_circle,
                            color: _queueGreen, size: 22),
                      )
                    : Semantics(
                        label: 'Add to queue',
                        button: true,
                        child: ElevatedButton.icon(
                          onPressed: onQueue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _queueGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: _tsSm),
                            minimumSize: const Size(_kMinTarget, _kMinTarget),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('QUEUE'),
                        ),
                      ),
              ]),
            ),
          ),
        ),
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

            // Fullscreen toggle button (top-right); always directly toggles.
            // Overlay visibility is controlled by cursor/pointer activity only.
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: _overlayVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Semantics(
                  label: widget.fullscreen
                      ? 'Exit fullscreen'
                      : 'Enter fullscreen',
                  button: true,
                  child: SizedBox(
                    width: _kMinTarget,
                    height: _kMinTarget,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _onCursorActivity();
                        widget.onToggle();
                      },
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                              color: _overlayBg, shape: BoxShape.circle),
                          child: Icon(
                            widget.fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
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
          // Softer fade: transparent shelf then gradual ramp to near-black
          colors: [Colors.transparent, Colors.transparent, Color(0xEA000000)],
          stops: [0.0, 0.15, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 28, 20, bottomPad + 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Seek bar ───────────────────────────────────────────────
          if (song != null) ...[
            Row(
              children: [
                Text(_fmt(player.position),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                Text(_fmt(player.duration),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
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
                            fontSize: _tsXs,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 3),
                    Text(
                      song?.title ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    if ((song?.artist ?? song?.folderName) != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            song!.artist != null
                                ? Icons.person_outline
                                : Icons.folder_outlined,
                            color: Colors.white38,
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              song.artist ?? song.folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _sub, fontSize: 12),
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
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _MediaButton(
                      onTap: notifier.togglePlayPause,
                      size: 44,
                      backgroundColor: _purple,
                      borderColor: Colors.transparent,
                      icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
                      iconColor: Colors.black,
                      iconSize: 24,
                      label: player.isPlaying ? 'PAUSE' : 'PLAY',
                      labelColor: _purple.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 14),
                    _MediaButton(
                      onTap: notifier.skip,
                      size: 36,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      borderColor: Colors.white38,
                      icon: Icons.skip_next,
                      iconColor: Colors.white,
                      iconSize: 20,
                      label: 'NEXT',
                      labelColor: Colors.white38,
                      tooltip: 'Skip to next song',
                    ),
                  ],
                ),
                const SizedBox(width: 16),
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
                                  fontSize: _tsXs,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white38,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 3),
                          Text(
                            next.song?.title ?? 'Song #${next.songId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                          if (next.song?.artist != null ||
                              next.song?.folderName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              next.song!.artist ?? next.song!.folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: _sub, fontSize: 12),
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
            const SizedBox(height: 8),
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
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 110,
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
                const SizedBox(width: 4),
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
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── Always-visible player control bar (normal / non-fullscreen view) ─────────

class _PlayerControlBar extends ConsumerWidget {
  const _PlayerControlBar({this.compact = false});

  /// When true (short screens / Android landscape), collapses to a single
  /// slim row: progress + mute icon + song title + play/pause + next.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(playerProvider);
    final player = playerAsync.valueOrNull;
    if (player == null || player.isIdle) return const SizedBox.shrink();

    final notifier = ref.read(playerProvider.notifier);
    final song = player.currentEntry?.song;

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = compact || constraints.maxWidth < 420;

      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A2235),
          border: Border(
            top: BorderSide(color: _border, width: 1),
            bottom: BorderSide(color: _border, width: 1),
          ),
        ),
        padding: EdgeInsets.fromLTRB(isNarrow ? 12 : 20, compact ? 4 : 8,
            isNarrow ? 12 : 20, compact ? 4 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNarrow) ...[
              // ── NARROW: 3-column — title (flex) | controls (fixed, centred) | volume (flex)
              // Equal Expanded on both sides guarantees controls are always
              // geometrically centred. Title truncates with ellipsis naturally.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Left: title + artist, truncates at midpoint ─────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song?.title ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: _tsBase,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if ((song?.artist ?? song?.folderName) != null)
                          Text(
                            song!.artist ?? song.folderName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: _sub, fontSize: _tsSm),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _sp8),
                  // ── Centre: Play/Pause + Next (fixed, never squeezed) ───
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: player.isPlaying ? 'Pause' : 'Play',
                        button: true,
                        child: GestureDetector(
                          onTap: notifier.togglePlayPause,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: _purple,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              player.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.black,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: _sp8),
                      Semantics(
                        label: 'Skip to next',
                        button: true,
                        child: GestureDetector(
                          onTap: notifier.skip,
                          child: SizedBox(
                            width: _kMinTarget,
                            height: _kMinTarget,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Icon(
                                  Icons.skip_next,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: _sp8),
                  // ── Right: volume icon + slider, same flex as title ─────
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Volume icon — tight, no excess padding
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
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 110,
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
                      ],
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
                            fontSize: _tsXs,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                            letterSpacing: 1.2,
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
                        labelColor: _purple.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 18),
                      _MediaButton(
                        onTap: notifier.skip,
                        size: 44,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
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
    final buttonWidget = SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
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
      ),
    );

    return Semantics(
      label: label,
      button: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tooltip != null
              ? Tooltip(message: tooltip!, child: buttonWidget)
              : buttonWidget,
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: _tsXs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── No-folder inline prompt (shown in sidebar when no folder is set) ─────────

class _NoFolderPrompt extends StatelessWidget {
  const _NoFolderPrompt({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: _sp24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.4,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _queueGreen.withValues(alpha: 0.12),
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

// ── Resizer handles ───────────────────────────────────────────────────────────

/// Vertical divider that lets the user drag to resize the sidebar width.
/// Shows a 3-dot grip on hover to signal its interactivity.
class _SidebarResizer extends StatefulWidget {
  const _SidebarResizer({required this.onDragUpdate});
  final void Function(double dx) onDragUpdate;

  @override
  State<_SidebarResizer> createState() => _SidebarResizerState();
}

class _SidebarResizerState extends State<_SidebarResizer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => widget.onDragUpdate(d.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 8,
          color: _hovered ? _border.withValues(alpha: 0.8) : _border,
          child: _hovered
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                        3,
                        (_) => Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: const BoxDecoration(
                                  color: Colors.white38,
                                  shape: BoxShape.circle),
                            )),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Horizontal divider that lets the user drag to resize the queue panel height.
class _QueueResizer extends StatefulWidget {
  const _QueueResizer({required this.onDragUpdate});
  final void Function(double dy) onDragUpdate;

  @override
  State<_QueueResizer> createState() => _QueueResizerState();
}

class _QueueResizerState extends State<_QueueResizer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onVerticalDragUpdate: (d) => widget.onDragUpdate(d.delta.dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 16,
          color: const Color(0xFF111827),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _hovered ? 64 : 48,
              height: _hovered ? 5 : 4,
              decoration: BoxDecoration(
                color: _hovered ? Colors.white54 : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Queue panel ──────────────────────────────────────────────────────────────

class _QueuePanel extends ConsumerStatefulWidget {
  const _QueuePanel({required this.queue, required this.height});
  final List<QueueEntry> queue;
  final double height;

  @override
  ConsumerState<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<_QueuePanel> {
  // Start collapsed on narrow/short screens to save vertical space.
  late bool _collapsed = Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final unifiedQueue =
        ref.watch(playerProvider).valueOrNull?.unifiedQueue ?? const [];
    final totalCount = unifiedQueue.length;
    final pad = widget.height < 160 ? 8.0 : _sp16;
    final nextItem = unifiedQueue.isNotEmpty ? unifiedQueue.first : null;

    // ── Collapsible header ──────────────────────────────────────────
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _collapsed = !_collapsed),
      child: Row(children: [
        const Icon(Icons.queue_music_rounded, color: Colors.white54, size: 18),
        const SizedBox(width: 6),
        const Text('Up Next',
            style: TextStyle(
                fontSize: _tsBase,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        if (totalCount > 0) ...[
          const SizedBox(width: _sp8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: _purple.withValues(alpha: 0.4), width: 1),
            ),
            child: Text('$totalCount',
                style: const TextStyle(
                    color: _purple,
                    fontSize: _tsXs,
                    fontWeight: FontWeight.bold)),
          ),
        ],
        // ── Next song teaser shown while collapsed ────────────────────
        if (_collapsed && nextItem != null) ...[
          const SizedBox(width: _sp12),
          Expanded(
            child: Text(
              nextItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: _tsSm,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ] else
          const Spacer(),
        AnimatedRotation(
          turns: _collapsed ? 0.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: const Icon(Icons.keyboard_arrow_up,
              color: Colors.white54, size: 20),
        ),
      ]),
    );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _sidebarBg,
          border: Border(top: BorderSide(color: _border, width: 1)),
        ),
        padding: EdgeInsets.all(pad),
        child: Builder(builder: (ctx) {
          // Account for SafeArea bottom inset (macOS dock, Android nav bar, etc.)
          // so the animated body height never overflows.
          final safeBottom = MediaQuery.paddingOf(ctx).bottom;
          // 36px = generous header height that covers any font/density combo.
          final bodyH =
              (widget.height - safeBottom - pad * 2 - 36).clamp(0.0, 9999.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              // AnimatedContainer height: 0 ↔ bodyH drives the collapse.
              // No Expanded wrapper — tight parent constraints must NOT be applied
              // here or the explicit height is ignored by the layout engine.
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _collapsed ? 0 : bodyH,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Padding(
                  padding: const EdgeInsets.only(top: _sp8),
                  child: SizedBox(
                    height: bodyH - _sp8,
                    child: totalCount == 0
                        ? const Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.queue_music_rounded,
                                      size: 36, color: Colors.white12),
                                  SizedBox(height: 10),
                                  Text('Queue is empty',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: _tsBase,
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(height: 4),
                                  Text('Add songs from the list on the left',
                                      style: TextStyle(
                                          color: Colors.white24,
                                          fontSize: _tsSm),
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
                ),
              ),
            ],
          );
        }),
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
    final accentColor = isYoutube ? _blue : _queueGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: _sp8),
      decoration: BoxDecoration(
          color: _cardBg, borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: _cardHover.withValues(alpha: 0.4),
            splashColor: Colors.white10,
            onTap: null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: _sp12, vertical: _sp8),
              child: Row(children: [
                // ── Source badge ──────────────────────────────────────────
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: _sp8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isYoutube ? Icons.language : Icons.music_note,
                    size: 12,
                    color: accentColor,
                  ),
                ),
                // ── Position ──────────────────────────────────────────────
                Text('$position. ',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: _tsSm)),
                // ── Title ─────────────────────────────────────────────────
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: _tsBase)),
                ),
                if (onRemove != null)
                  // Min 44×44 touch target wrapping a smaller visual
                  Semantics(
                    label: 'Remove from queue',
                    button: true,
                    child: SizedBox(
                      width: _kMinTarget,
                      height: _kMinTarget,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white54, size: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Narrow layout tab bar ──────────────────────────────────────────────────────
// ── Phone chip tab bar ────────────────────────────────────────────────────────

class _PhoneChipBar extends StatelessWidget {
  const _PhoneChipBar({
    required this.activeTab,
    required this.queueCount,
    required this.onTab,
  });
  final int activeTab;
  final int queueCount;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _sidebarBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _Chip(
            label: 'Songs',
            icon: Icons.library_music_outlined,
            selected: activeTab == 0,
            onTap: () => onTab(0),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: queueCount > 0 ? 'Queue  $queueCount' : 'Queue',
            icon: Icons.queue_music_rounded,
            selected: activeTab == 1,
            onTap: () => onTab(1),
            badge: queueCount,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _purple.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _purple.withValues(alpha: 0.6) : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? _purple : Colors.white38),
            const SizedBox(width: 6),
            Text(
              badge > 0 ? label.split('  ').first : label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? _purple : Colors.white38,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? _purple : Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Phone queue list (for narrow layout Tab 1) ────────────────────────────────

class _PhoneQueueList extends ConsumerWidget {
  const _PhoneQueueList({required this.queue});
  final List<QueueEntry> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unifiedQueue =
        ref.watch(playerProvider).valueOrNull?.unifiedQueue ?? const [];

    if (unifiedQueue.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_rounded, size: 48, color: Colors.white12),
            SizedBox(height: 12),
            Text('Queue is empty',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Add songs from the Songs tab',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: unifiedQueue.length,
      itemBuilder: (_, i) {
        final item = unifiedQueue[i];
        return _QueueItem(
          label: item.title,
          position: i + 1,
          isYoutube: item.isYoutube,
          onRemove: () =>
              ref.read(playerProvider.notifier).removeQueueItemAt(i),
        );
      },
    );
  }
}
