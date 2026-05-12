// lib/features/player/presentation/mini_player.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(playerProvider).when(
      data: (state) {
        if (state.currentEntry == null) return const SizedBox.shrink();
        return _MiniPlayerContent(state: state);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MiniPlayerContent extends ConsumerWidget {
  const _MiniPlayerContent({required this.state});

  final KaraokePlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    final song = state.currentEntry!.song;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.player),
      child: Container(
        height: 72,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: Color(0xFF2A2A4A))),
        ),
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: state.progressFraction,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
              minHeight: 2,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Music icon
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.music_note,
                          color: AppTheme.primary, size: 18),
                    ),
                    const Gap(12),
                    // Song info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            song?.title ?? 'Unknown',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            song?.artist ?? song?.folderName ?? '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Controls
                    IconButton(
                      icon: Icon(
                        state.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: AppTheme.primary,
                      ),
                      onPressed: notifier.togglePlayPause,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white54),
                      onPressed: notifier.skip,
                    ),
                    // TV overlay button
                    IconButton(
                      icon: const Icon(Icons.tv, color: Colors.white38),
                      tooltip: 'Karaoke View',
                      onPressed: () => context.push(AppRoutes.overlay),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
