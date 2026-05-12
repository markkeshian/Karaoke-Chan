// lib/features/player/data/player_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';

class PlayerNotifier extends AsyncNotifier<KaraokePlayerState> {
  late Player _player;
  VideoController? videoController;
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;
  // Prevents _onTrackCompleted from firing while skip/advance is in progress
  // AND prevents concurrent advances from stacking up.
  bool _isAdvancing = false;

  @override
  Future<KaraokePlayerState> build() async {
    _disposed = false;
    _player = Player();
    videoController = VideoController(_player);
    _attachListeners();
    ref.onDispose(() {
      _disposed = true;
      for (final s in _subs) {
        s.cancel();
      }
      _player.dispose();
    });
    return const KaraokePlayerState();
  }

  void _attachListeners() {
    _subs.add(_player.stream.playing.listen((playing) {
      _update((s) {
        if (playing) return s.copyWith(status: PlayerStatus.playing);
        // Don't overwrite 'idle' with 'paused' — idle is set explicitly by
        // _advanceQueue when the queue is empty. The playing=false event from
        // player.stop() arrives asynchronously AFTER we set idle, and would
        // otherwise reset it to paused, breaking the "add song → auto-play" flow.
        if (s.isIdle) return s;
        return s.copyWith(status: PlayerStatus.paused);
      });
    }));
    _subs.add(_player.stream.position.listen((pos) {
      _update((s) => s.copyWith(position: pos));
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      _update((s) => s.copyWith(duration: dur));
    }));
    _subs.add(_player.stream.completed.listen((completed) {
      if (completed && !_isAdvancing) _onTrackCompleted();
    }));
    _subs.add(_player.stream.error.listen((err) {
      _update((s) => s.copyWith(status: PlayerStatus.error, errorMessage: err));
    }));
    _subs.add(_player.stream.tracks.listen((tracks) {
      // A real video track has an id that is not the sentinel 'no' value.
      // We update hasVideo whenever the track list changes (e.g. after open()).
      final hasVideo = tracks.video.any((t) => t.id != 'no' && t.id != '');
      _update((s) => s.copyWith(hasVideo: hasVideo));
    }));

    // Also detect video via the track state stream (fires once media is opened).
    _subs.add(_player.stream.track.listen((track) {
      final hasVideo = track.video.id != 'no' && track.video.id != '';
      _update((s) => s.copyWith(hasVideo: hasVideo));
    }));
  }

  Future<void> playEntry(QueueEntry entry) async {
    if (_disposed) return;
    final song = entry.song;
    if (song == null) return;

    _update((s) => s.copyWith(
          currentEntry: entry,
          status: PlayerStatus.loading,
          position: Duration.zero,
          duration: Duration.zero,
          hasVideo: false,
        ));

    await _player.open(Media(Uri.file(song.filePath).toString()));

    if (entry.id != null) {
      await ref.read(queueRepositoryProvider).markPlaying(entry.id!);
    }
  }

  Future<void> play() async => _player.play();
  Future<void> pause() async => _player.pause();
  Future<void> togglePlayPause() async => _player.playOrPause();

  /// Immediately stops playback and resets to idle without advancing the queue.
  /// Used by the full app reset flow.
  Future<void> stopToIdle() async {
    _isAdvancing = true; // block _onTrackCompleted from firing
    try {
      await _player.stop();
      _update((s) => s.copyWith(
          status: PlayerStatus.idle, clearEntry: true, hasVideo: false));
    } finally {
      _isAdvancing = false;
    }
  }

  Future<void> seek(Duration position) async => _player.seek(position);

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume * 100);
    _update((s) => s.copyWith(volume: volume));
  }

  Future<void> skip() async {
    if (_isAdvancing) return;
    final current = state.value?.currentEntry;
    if (current?.id != null) {
      await ref.read(queueRepositoryProvider).markSkipped(current!.id!);
    }
    await _advanceQueue(doneEntryId: current?.id);
  }

  /// Unified advance logic — called by [skip] and [_onTrackCompleted].
  /// [doneEntryId] is excluded when searching for the next entry (it has
  /// already been marked done/skipped in the DB by the caller).
  Future<void> _advanceQueue({required int? doneEntryId}) async {
    if (_isAdvancing || _disposed) return;
    _isAdvancing = true;
    try {
      final queue = await ref.read(queueRepositoryProvider).getActive();
      // Exclude the just-finished/skipped entry in case the DB update hasn't
      // propagated yet (belt-and-suspenders).
      final next = queue.where((e) => e.id != doneEntryId).firstOrNull;

      if (next != null) {
        await playEntry(next);
      } else {
        await _player.stop();
        _update((s) => s.copyWith(
            status: PlayerStatus.idle, clearEntry: true, hasVideo: false));
      }
      await ref.read(queueNotifierProvider.notifier).refresh();
    } finally {
      _isAdvancing = false;
    }
  }

  /// Enqueues [song] and immediately plays it, regardless of what is in the
  /// queue. Used by the single-screen stage when the user taps a song while
  /// nothing is playing.
  Future<void> playNow(Song song) async {
    if (_disposed) return;
    if (song.id == null) return;
    // Enqueue so the DB has a proper record (auto-advance uses queue).
    final entry = await ref.read(queueRepositoryProvider).enqueue(song.id!);
    // Attach the full Song object so the UI can show title/artist immediately.
    await playEntry(entry.copyWith(song: song));
    // Refresh queue UI.
    await ref.read(queueNotifierProvider.notifier).refresh();
  }

  Future<void> _onTrackCompleted() async {
    if (_isAdvancing || _disposed) return;
    final current = state.value?.currentEntry;
    if (current == null) return;

    if (current.id != null) {
      await ref.read(queueRepositoryProvider).markDone(current.id!);
    }
    await ref.read(songRepositoryProvider).incrementPlayCount(current.songId);
    await _advanceQueue(doneEntryId: current.id);
  }

  void _update(KaraokePlayerState Function(KaraokePlayerState) fn) {
    if (state.hasValue) state = AsyncData(fn(state.value!));
  }
}

final playerProvider =
    AsyncNotifierProvider<PlayerNotifier, KaraokePlayerState>(
        PlayerNotifier.new);
