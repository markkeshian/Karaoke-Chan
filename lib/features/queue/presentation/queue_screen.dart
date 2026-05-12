// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:reorderables/reorderables.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/core/widgets/neon_card.dart';
import 'package:karaoke_chan/features/queue/presentation/add_song_screen.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          queue.when(
            data: (entries) => entries.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Clear all',
                    onPressed: () =>
                        ref.read(queueNotifierProvider.notifier).clearAll(),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: queue.when(
        data: (entries) => entries.isEmpty
            ? const _EmptyQueue()
            : _QueueList(entries: entries),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddSongSheet(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Song', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.queue_music, size: 80, color: Colors.white12),
          const Gap(16),
          Text('Queue is empty',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white38)),
          const Gap(8),
          Text('Tap "Add Song" to get started',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white24)),
        ],
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.entries});

  final List<QueueEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableColumn(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      onReorder: (oldIdx, newIdx) {
        final list = List<QueueEntry>.from(entries);
        final item = list.removeAt(oldIdx);
        list.insert(newIdx, item);
        ref.read(queueNotifierProvider.notifier).reorder(list);
      },
      footer: const Gap(100),
      children: entries
          .map((e) => _QueueTile(key: ValueKey(e.id), entry: e))
          .toList(),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({super.key, required this.entry});

  final QueueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = entry.status == QueueStatus.playing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: NeonCard(
        glowColor: isPlaying ? AppTheme.primary : null,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: isPlaying
                ? AppTheme.primary.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            child: isPlaying
                ? const Icon(Icons.graphic_eq,
                    color: AppTheme.primary, size: 20)
                : Text(
                    '${entry.position + 1}',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
          ),
          title: Text(
            entry.song?.title ?? 'Unknown',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isPlaying ? AppTheme.primary : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.song?.artist != null)
                Text(entry.song!.artist!,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              if (entry.song?.folderName != null)
                Text(entry.song!.folderName!,
                    style:
                        const TextStyle(color: Colors.white30, fontSize: 11)),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.song?.displayDuration ?? '--:--',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12)),
              if (!isPlaying) ...[
                const Gap(4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.white38,
                  onPressed: () {
                    if (entry.id != null) {
                      ref
                          .read(queueNotifierProvider.notifier)
                          .remove(entry.id!);
                    }
                  },
                ),
              ],
              const Icon(Icons.drag_handle, color: Colors.white24, size: 20),
            ],
          ),
          onTap: isPlaying
              ? null
              : () async {
                  await ref
                      .read(playerProvider.notifier)
                      .playEntry(entry);
                  ref.read(queueNotifierProvider.notifier).refresh();
                },
        ),
      ),
    );
  }
}
