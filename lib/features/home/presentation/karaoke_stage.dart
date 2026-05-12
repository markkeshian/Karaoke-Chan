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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

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
  bool _fullscreen = false;
  bool _isChangingFolder = false;
  double? _sidebarWidth;
  double _queueHeight = 220;

  @override
  void dispose() {
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyF) {
      setState(() => _fullscreen = !_fullscreen);
    } else if (key == LogicalKeyboardKey.escape && _fullscreen) {
      setState(() => _fullscreen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final playerAsync = ref.watch(playerProvider);
    final queueAsync = ref.watch(queueNotifierProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
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

            final player =
                playerAsync.valueOrNull ?? const KaraokePlayerState();
            final queue = queueAsync.valueOrNull ?? [];

            return Row(
              children: [
                if (!_fullscreen) ...[
                  _Sidebar(
                    library: library,
                    searchCtrl: _search,
                    sidebarWidth: _sidebarWidth ??
                        MediaQuery.sizeOf(context).width * 0.35,
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
                  ),
                  // ── Sidebar drag resizer ──────────────────────────────
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          _sidebarWidth = ((_sidebarWidth ??
                                      MediaQuery.sizeOf(context).width * 0.35) +
                                  d.delta.dx)
                              .clamp(200.0,
                                  MediaQuery.sizeOf(context).width * 0.65);
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
                          onToggle: () =>
                              setState(() => _fullscreen = !_fullscreen),
                        ),
                      ),
                      if (!_fullscreen) ...[
                        // ── Queue panel drag resizer ────────────────────
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: GestureDetector(
                            onVerticalDragUpdate: (d) {
                              final maxQueue =
                                  MediaQuery.sizeOf(context).height * 0.40;
                              setState(() {
                                _queueHeight = (_queueHeight - d.delta.dy)
                                    .clamp(130.0, maxQueue);
                              });
                            },
                            child: Container(
                              height: 28,
                              color: _border,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      height: 4,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white30,
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(2)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
      ),
    );
  }

  void _queueSong(Song song, KaraokePlayerState player) {
    if (song.id == null) return;
    if (player.isIdle) {
      ref.read(playerProvider.notifier).playNow(song);
    } else {
      ref.read(queueNotifierProvider.notifier).enqueue(song.id!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${song.title}" added to queue'),
        duration: const Duration(seconds: 2),
        backgroundColor: _cardBg,
      ));
    }
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
                  const Text('🎤', style: TextStyle(fontSize: 64)),
                  const Gap(16),
                  const Text('Karaoke Queue',
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
                  const Text('Supports MP4 · MKV · AVI · MP3 · FLAC · and more',
                      style: TextStyle(color: Colors.white30, fontSize: 12)),
                ]),
              ),
            ),
          ),
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
    required this.sidebarWidth,
    required this.currentSongId,
    required this.queuedSongIds,
    required this.onQueue,
    required this.onChangeFolder,
  });

  final LibraryState library;
  final TextEditingController searchCtrl;
  final double sidebarWidth;
  final int? currentSongId;
  final Set<int> queuedSongIds;
  final void Function(Song) onQueue;
  final VoidCallback onChangeFolder;

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
                      const Expanded(
                        child: Text('🎤  Karaoke Queue',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined,
                            color: Colors.white38, size: 18),
                        tooltip: 'Settings',
                        onPressed: () => context.push(AppRoutes.settings),
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_open_outlined,
                            color: Colors.white38, size: 18),
                        tooltip: 'Change folder',
                        onPressed: onChangeFolder,
                      ),
                    ]),
                    const Gap(12),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchCtrl,
                      builder: (context, value, _) => TextField(
                        controller: searchCtrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search songs...',
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
                        onChanged: (q) =>
                            ref.read(libraryProvider.notifier).search(q),
                      ),
                    ),
                  ]),
            ),

            // ── Song list ──────────────────────────────────────────────────
            Expanded(
              child: library.songs.isEmpty
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
          const Gap(12),
          ElevatedButton.icon(
            onPressed: widget.isQueued ? null : widget.onQueue,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  widget.isQueued ? const Color(0xFF374151) : _queueGreen,
              foregroundColor: widget.isQueued ? Colors.white38 : Colors.white,
              disabledBackgroundColor: const Color(0xFF374151),
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              minimumSize: Size.zero,
            ),
            icon: widget.isQueued
                ? const Icon(Icons.check, size: 14)
                : const Icon(Icons.add, size: 14),
            label: Text(widget.isQueued ? 'QUEUED' : 'QUEUE'),
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
            if (!player.isIdle && !player.hasVideo && !player.hasError)
              const Center(
                child: Text(
                  '♫  Playing Audio',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 22),
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

            // Controls fade in/out on cursor idle
            AnimatedOpacity(
              opacity: _overlayVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: Stack(children: [
                // Fullscreen toggle (top-right)
                Positioned(
                  top: 20,
                  right: 20,
                  child: GestureDetector(
                    onTap: widget.onToggle,
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
                          size: 24),
                    ),
                  ),
                ),

                // Full-width bottom bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _NowPlayingOverlay(player: player, queue: queue),
                ),
              ]),
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
    final waiting =
        queue.where((e) => e.status == QueueStatus.waiting).toList();
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
            const Text('Queue List',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const Gap(12),
            Expanded(
              child: waiting.isEmpty
                  ? const Center(
                      child: Text('Queue is empty',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: waiting.length,
                      itemBuilder: (_, i) => _QueueItem(
                        entry: waiting[i],
                        position: i + 1,
                        onRemove: () => ref
                            .read(queueNotifierProvider.notifier)
                            .remove(waiting[i].id!),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem(
      {required this.entry, required this.position, required this.onRemove});
  final QueueEntry entry;
  final int position;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final song = entry.song;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _cardBg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Text(song?.title ?? 'Song #${entry.songId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14)),
        ),
        if (song?.artist != null || song?.folderName != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(song!.artist ?? song.folderName ?? '',
                style: const TextStyle(color: _sub, fontSize: 12)),
          ),
        const Gap(12),
        Text('#$position',
            style: const TextStyle(
                color: _sub, fontWeight: FontWeight.bold, fontSize: 14)),
        const Gap(8),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close, color: Colors.white38, size: 16),
        ),
      ]),
    );
  }
}
