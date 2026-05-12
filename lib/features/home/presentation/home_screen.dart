// lib/features/home/presentation/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(playerProvider);
    final queueAsync = ref.watch(queueNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Now playing banner
                playerAsync.when(
                  data: (s) => s.currentEntry != null
                      ? _NowPlayingBanner(state: s)
                      : _WelcomeBanner(),
                  loading: () => _WelcomeBanner(),
                  error: (_, __) => _WelcomeBanner(),
                ),
                const Gap(20),
                // Queue preview
                queueAsync.when(
                  data: (entries) => _QueuePreview(entries: entries),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                ),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addSong),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Song'),
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      backgroundColor: AppTheme.background,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Karaoke Chan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.15),
            AppTheme.secondary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎤 Ready to Sing?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          const Text(
            'Add songs to the queue to start your karaoke session.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const Gap(16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _TipChip(icon: Icons.folder_open, label: 'Pick a folder in Library'),
              _TipChip(icon: Icons.search, label: 'Search songs'),
              _TipChip(icon: Icons.queue_music, label: 'Add to queue'),
              _TipChip(icon: Icons.wifi, label: 'Remote queue via phone'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const Gap(6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _NowPlayingBanner extends ConsumerWidget {
  const _NowPlayingBanner({required this.state});
  final KaraokePlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    final song = state.currentEntry!.song;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.player),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary.withValues(alpha: 0.25), AppTheme.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.music_note, color: AppTheme.primary, size: 24),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NOW PLAYING',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        song?.title ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song?.artist ?? song?.folderName ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    state.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: AppTheme.primary,
                    size: 40,
                  ),
                  onPressed: notifier.togglePlayPause,
                ),
              ],
            ),
            const Gap(12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: state.progressFraction,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation(AppTheme.primary),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuePreview extends ConsumerWidget {
  const _QueuePreview({required this.entries});
  final List<QueueEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = entries
        .where((e) => e.status == QueueStatus.waiting)
        .take(5)
        .toList();

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Up Next',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.queue),
              child: const Text('See all'),
            ),
          ],
        ),
        const Gap(8),
        ...upcoming.asMap().entries.map((e) {
          final idx = e.key;
          final entry = e.value;
          final song = entry.song;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              child: Text(
                '${idx + 1}',
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              song?.title ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song?.artist ?? song?.folderName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38),
            ),
          );
        }),
      ],
    );
  }
}
