// lib/features/queue/presentation/add_song_screen.dart
// Displayed as a modal bottom sheet from QueueScreen so the user never
// leaves the queue tab.  Can still be pushed as a full route if needed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/core/widgets/neon_card.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

/// Shows the add-song picker as a full-height modal bottom sheet.
Future<void> showAddSongSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: _AddSongSheetContent(scrollController: scrollController),
      ),
    ),
  );
}

class _AddSongSheetContent extends ConsumerStatefulWidget {
  const _AddSongSheetContent({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_AddSongSheetContent> createState() =>
      _AddSongSheetContentState();
}

class _AddSongSheetContentState extends ConsumerState<_AddSongSheetContent> {
  final _searchController = TextEditingController();
  Song? _selected;
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addToQueue() async {
    if (_selected == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(queueNotifierProvider.notifier)
          .addToQueue(_selected!.id!);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);

    return Material(
      color: AppTheme.surface,
      child: Column(
        children: [
          // ── Handle + header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add Song to Queue',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // ── Search field ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search songs…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) => ref.read(libraryProvider.notifier).search(q),
            ),
          ),
          // ── Song list ────────────────────────────────────────────────────
          Expanded(
            child: libraryAsync.when(
              data: (lib) {
                if (!lib.hasFolder) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off, size: 64, color: Colors.white24),
                        Gap(12),
                        Text(
                          'No folder selected yet.\nGo to Library first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  );
                }
                if (lib.songs.isEmpty) {
                  return const Center(
                    child: Text('No songs found',
                        style: TextStyle(color: Colors.white38)),
                  );
                }
                return ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lib.songs.length,
                  itemBuilder: (ctx, i) {
                    final song = lib.songs[i];
                    final isSelected = song.id == _selected?.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: NeonCard(
                        glowColor: isSelected ? AppTheme.primary : null,
                        onTap: () => setState(() => _selected = song),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.white24,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppTheme.primary : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (song.artist != null)
                                Text(song.artist!,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                              if (song.folderName != null)
                                Text(song.folderName!,
                                    style: const TextStyle(
                                        color: Colors.white30, fontSize: 11)),
                            ],
                          ),
                          trailing: Text(
                            song.displayDuration,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          // ── Confirm button ───────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: (_loading || _selected == null) ? null : _addToQueue,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.add_to_queue),
                label: Text(_selected == null
                    ? 'Select a song'
                    : 'Add "${_selected!.title}" to Queue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full-screen wrapper (kept for router compatibility) ────────────────────────

/// Wraps [_AddSongSheetContent] as a standalone screen when navigated to
/// directly (e.g. deep-link or keyboard shortcut).
class AddSongScreen extends ConsumerWidget {
  const AddSongScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: _AddSongSheetContent(
        scrollController: ScrollController(),
      ),
    );
  }
}
