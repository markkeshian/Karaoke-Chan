// lib/features/player/presentation/player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(playerProvider).when(
      data: (state) => _PlayerContent(state: state),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _PlayerContent extends ConsumerWidget {
  const _PlayerContent({required this.state});

  final KaraokePlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    final entry = state.currentEntry;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: const Text('Now Playing'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tv_outlined),
            tooltip: 'Karaoke View',
            onPressed: () => context.push('/overlay'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Video / album art
          Expanded(
            flex: 5,
            child: _MediaView(state: state),
          ),

          // Song info
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: _SongInfo(entry: entry),
          ),

          // Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: _ProgressRow(state: state, notifier: notifier),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _Controls(state: state, notifier: notifier),
          ),
        ],
      ),
    );
  }
}

class _MediaView extends ConsumerWidget {
  const _MediaView({required this.state});
  final KaraokePlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    if (notifier.videoController != null && state.hasVideo) {
      return Video(controller: notifier.videoController!);
    }
    // Audio-only fallback
    return Container(
      color: Colors.black,
      child: Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.music_note, size: 64, color: AppTheme.primary),
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.entry});
  final QueueEntry? entry;

  @override
  Widget build(BuildContext context) {
    final song = entry?.song;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song?.title ?? 'No Song Playing',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap(4),
        Text(
          song?.artist ?? song?.folderName ?? '',
          style: const TextStyle(color: Colors.white54, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.state, required this.notifier});
  final KaraokePlayerState state;
  final PlayerNotifier notifier;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: Colors.white12,
            thumbColor: AppTheme.primary,
            overlayColor: AppTheme.primary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: state.progressFraction,
            onChanged: (v) {
              if (state.duration > Duration.zero) {
                notifier.seek(state.duration * v);
              }
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(state.position),
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            Text(_fmt(state.duration),
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.state, required this.notifier});
  final KaraokePlayerState state;
  final PlayerNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Volume
        IconButton(
          icon: const Icon(Icons.volume_up_outlined, color: Colors.white54),
          onPressed: () => _showVolumeDialog(context, state, notifier),
        ),
        // Play / Pause
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              state.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 32,
              color: Colors.black,
            ),
            onPressed: notifier.togglePlayPause,
          ),
        ),
        // Skip
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white54, size: 32),
          onPressed: notifier.skip,
        ),
      ],
    );
  }

  void _showVolumeDialog(
      BuildContext context, KaraokePlayerState state, PlayerNotifier notifier) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _VolumeSheet(state: state, notifier: notifier),
    );
  }
}

class _VolumeSheet extends StatelessWidget {
  const _VolumeSheet({required this.state, required this.notifier});
  final KaraokePlayerState state;
  final PlayerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Volume', style: TextStyle(fontWeight: FontWeight.bold)),
          const Gap(16),
          Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  value: state.volume,
                  onChanged: notifier.setVolume,
                  activeColor: AppTheme.primary,
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
        ],
      ),
    );
  }
}
