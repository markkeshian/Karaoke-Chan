// lib/features/player/data/player_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';

class PlayerNotifier extends AsyncNotifier<KaraokePlayerState> {
  late Player _player;
  VideoController? videoController;
  final List<StreamSubscription> _subs = [];

  @override
  Future<KaraokePlayerState> build() async {
    _player = Player();
    videoController = VideoController(_player);
    _attachListeners();
    ref.onDispose(() {
      for (final s in _subs) s.cancel();
      _player.dispose();
    });
    return const KaraokePlayerState();
  }

  void _attachListeners() {
    _subs.add(_player.stream.playing.listen((playing) {
      _update((s) => s.copyWith(
            status: playing ? PlayerStatus.playing : PlayerStatus.paused,
          ));
    }));
    _subs.add(_player.stream.position.listen((pos) {
      _update((s) => s.copyWith(position: pos));
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      _update((s) => s.copyWith(duration: dur));
    }));
    _subs.add(_player.stream.completed.listen((completed) {
      if (completed) _onTrackCompleted();
    }));
    _subs.add(_player.stream.error.listen((err) {
      _update((s) => s.copyWith(status: PlayerStatus.error, errorMessage: err));
    }));
    _subs.add(_player.stream.tracks.listen((tracks) {
      // A real video track has an id that is not the sentinel 'no' value.
      final hasVideo = tracks.video.any((t) => t.id != 'no');
      _update((s) => s.copyWith(hasVideo: hasVideo));
    }));
  }

  Future<void> playEntry(QueueEntry entry) async {
    final song = entry.song;
    if (song == null) return;

    _update((s) => s.copyWith(
          currentEntry: entry,
          status: PlayerStatus.loading,
          position: Duration.zero,
          duration: Duration.zero,
          hasVideo: false,
        ));

    await _player.open(Media(song.filePath));

    if (entry.id != null) {
      await ref.read(queueRepositoryProvider).markPlaying(entry.id!);
    }
  }

  Future<void> play() async => _player.play();
  Future<void> pause() async => _player.pause();
  Future<void> togglePlayPause() async => _player.playOrPause();

  Future<void> seek(Duration position) async => _player.seek(position);

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume * 100);
    _update((s) => s.copyWith(volume: volume));
  }

  Future<void> skip() async {
    final current = state.value?.currentEntry;
    if (current?.id != null) {
      await ref.read(queueRepositoryProvider).markSkipped(current!.id!);
    }
    await _player.stop();
    _update((s) => s.copyWith(status: PlayerStatus.idle, clearEntry: true));
  }

  Future<void> _onTrackCompleted() async {
    final current = state.value?.currentEntry;
    if (current == null) return;

    if (current.id != null) {
      await ref.read(queueRepositoryProvider).markDone(current.id!);
    }
    await ref.read(songRepositoryProvider).incrementPlayCount(current.songId);

    // Auto-advance
    final queue = await ref.read(queueRepositoryProvider).getActive();
    if (queue.isNotEmpty) {
      await playEntry(queue.first);
    } else {
      _update((s) => s.copyWith(status: PlayerStatus.idle, clearEntry: true));
    }
  }

  void _update(KaraokePlayerState Function(KaraokePlayerState) fn) {
    if (state.hasValue) state = AsyncData(fn(state.value!));
  }
}

final playerProvider =
    AsyncNotifierProvider<PlayerNotifier, KaraokePlayerState>(PlayerNotifier.new);
