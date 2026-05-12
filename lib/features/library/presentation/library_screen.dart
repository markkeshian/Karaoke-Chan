// lib/features/library/presentation/library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/core/widgets/neon_card.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          libraryAsync.when(
            data: (lib) => lib.hasFolder
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Re-scan folder',
                      onPressed: lib.isScanning
                          ? null
                          : () => ref.read(libraryProvider.notifier).scanFolder(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Change folder',
                      onPressed: () =>
                          ref.read(libraryProvider.notifier).changeFolder(),
                    ),
                  ])
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: libraryAsync.when(
        data: (lib) {
          if (!lib.hasFolder) return _FolderPickerView();
          if (lib.isScanning) return _ScanningView(state: lib);
          return _SongListView(state: lib, searchController: _searchController);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ─── No Folder Selected ───────────────────────────────────────────────────────

class _FolderPickerView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_special, size: 100, color: AppTheme.primary)
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut),
            const Gap(24),
            Text(
              'Select Karaoke Folder',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 26,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            Text(
              'Pick your main karaoke folder and the app will scan all nested subfolders automatically.',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              'Supports: MP4 · MKV · AVI · MOV · MP3 · FLAC · and more',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white30),
              textAlign: TextAlign.center,
            ),
            const Gap(40),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(libraryProvider.notifier).pickFolder(),
              icon: const Icon(Icons.folder_open, size: 22),
              label: const Text('Choose Folder'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const Gap(16),
            _FolderStructurePreview(),
          ],
        ),
      ),
    );
  }
}

class _FolderStructurePreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NeonCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Example structure',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppTheme.secondary)),
            const Gap(8),
            const _Tree(items: [
              '📁 Karaoke/',
              '  📁 English/',
              '    🎬 My Way.mp4',
              '    🎬 Hello.mkv',
              '  📁 OPM/',
              '    🎬 Sana.mp4',
              '  📁 HD/',
              '    🎬 Bohemian.mp4',
            ]),
          ],
        ),
      ),
    );
  }
}

class _Tree extends StatelessWidget {
  const _Tree({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(item,
                    style: const TextStyle(
                        fontFamily: 'monospace', color: Colors.white60, fontSize: 13)),
              ))
          .toList(),
    );
  }
}

// ─── Scanning Progress ────────────────────────────────────────────────────────

class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.totalCount == 0
        ? null
        : state.scannedCount / state.totalCount;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar, size: 72, color: AppTheme.primary)
                .animate(onPlay: (c) => c.repeat())
                .rotate(duration: 2.seconds),
            const Gap(24),
            Text(
              'Scanning Folder…',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppTheme.primary),
            ),
            const Gap(8),
            Text(
              '${state.scannedCount} songs found',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white54),
            ),
            const Gap(24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
            const Gap(8),
            Text(
              state.folderPath ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white30),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Song List ────────────────────────────────────────────────────────────────

class _SongListView extends ConsumerWidget {
  const _SongListView({
    required this.state,
    required this.searchController,
  });

  final LibraryState state;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Stats bar
        _StatsBar(state: state),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: 'Search songs, artists, folders…',
              prefixIcon: Icon(Icons.search),
              suffixIcon: null,
            ),
            onChanged: (q) =>
                ref.read(libraryProvider.notifier).search(q),
          ),
        ),
        // Song list
        Expanded(
          child: state.songs.isEmpty
              ? const _EmptySearch()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.songs.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SongTile(song: state.songs[i])
                        .animate(delay: Duration(milliseconds: i * 20))
                        .fadeIn(duration: 200.ms)
                        .slideX(begin: 0.05, end: 0),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surfaceVariant,
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 14, color: AppTheme.secondary),
          const Gap(6),
          Text(
            '${state.songs.length} songs',
            style: const TextStyle(color: AppTheme.secondary, fontSize: 13),
          ),
          const Gap(16),
          const Icon(Icons.folder, size: 14, color: Colors.white38),
          const Gap(6),
          Expanded(
            child: Text(
              state.folderPath ?? '',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.lastScanTime != null)
            Text(
              'Scanned ${_timeAgo(state.lastScanTime!)}',
              style:
                  const TextStyle(color: Colors.white24, fontSize: 11),
            ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SongTile extends ConsumerWidget {
  const _SongTile({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeonCard(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.music_note,
              color: AppTheme.secondary, size: 22),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (song.artist != null)
              Text(song.artist!,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12)),
            if (song.folderName != null)
              Row(children: [
                const Icon(Icons.folder_outlined,
                    size: 11, color: Colors.white30),
                const Gap(3),
                Text(song.folderName!,
                    style: const TextStyle(
                        color: Colors.white30, fontSize: 11)),
              ]),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white38),
          color: AppTheme.surface,
          onSelected: (action) async {
            if (action == 'delete' && song.id != null) {
              await ref
                  .read(songRepositoryProvider)
                  .delete(song.id!);
              ref.invalidate(libraryProvider);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, color: AppTheme.error, size: 18),
                Gap(8),
                Text('Remove', style: TextStyle(color: AppTheme.error)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.white12),
          Gap(12),
          Text('No songs match your search',
              style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}
