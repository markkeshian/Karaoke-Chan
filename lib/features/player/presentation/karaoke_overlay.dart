// lib/features/player/presentation/karaoke_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/player/data/player_notifier.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';

class KaraokeOverlay extends ConsumerWidget {
  const KaraokeOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(playerProvider).when(
      data: (state) => _OverlayContent(state: state),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
    );
  }
}

class _OverlayContent extends ConsumerStatefulWidget {
  const _OverlayContent({required this.state});
  final KaraokePlayerState state;

  @override
  ConsumerState<_OverlayContent> createState() => _OverlayContentState();
}

class _OverlayContentState extends ConsumerState<_OverlayContent> {
  bool _controlsVisible = true;

  void _toggleControls() =>
      setState(() => _controlsVisible = !_controlsVisible);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(playerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (notifier.videoController != null && state.hasVideo)
              Video(controller: notifier.videoController!)
            else
              const _AudioBackground(),

            // Top bar
            if (_controlsVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(state: state, notifier: notifier),
              ),

            // Bottom HUD
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BottomHud(state: state, notifier: notifier,
                  controlsVisible: _controlsVisible),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioBackground extends StatelessWidget {
  const _AudioBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D0D1A), Color(0xFF1A0D2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note, size: 120, color: Color(0x33BB86FC)),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.state, required this.notifier});
  final KaraokePlayerState state;
  final PlayerNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = state.currentEntry?.song;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black87, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 20,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
            onPressed: () => context.pop(),
          ),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? 'No Song',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song?.artist ?? song?.folderName ?? '',
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: notifier.togglePlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white70),
                onPressed: notifier.skip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomHud extends ConsumerWidget {
  const _BottomHud({
    required this.state,
    required this.notifier,
    required this.controlsVisible,
  });
  final KaraokePlayerState state;
  final PlayerNotifier notifier;
  final bool controlsVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(queueNotifierProvider);
    final nextEntry = queueAsync.value
        ?.where((e) => e.status == QueueStatus.waiting)
        .firstOrNull;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black87],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppTheme.primary,
            ),
            child: Slider(
              value: state.progressFraction,
              onChanged: controlsVisible
                  ? (v) {
                      if (state.duration > Duration.zero) {
                        notifier.seek(state.duration * v);
                      }
                    }
                  : null,
            ),
          ),

          // Next up
          if (nextEntry != null) ...[
            const Gap(8),
            Row(
              children: [
                const Icon(Icons.queue_music, color: Colors.white38, size: 16),
                const Gap(6),
                const Text(
                  'NEXT: ',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      letterSpacing: 1),
                ),
                Expanded(
                  child: Text(
                    nextEntry.song?.title ?? 'Unknown',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
