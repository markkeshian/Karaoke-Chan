// lib/features/player/data/player_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:karaoke_chan/core/services/youtube_service.dart';
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

  /// In-memory ordered queue — preserves insertion order across local + YouTube.
  final List<UnifiedQueueItem> _orderedQueue = [];

  /// Pre-fetched stream URLs keyed by videoId — populated when a YouTube
  /// video is queued so it's ready by the time it's their turn to play.
  final Map<String, String> _streamUrlCache = {};

  /// Debounce timer for the paused state on YouTube songs — prevents brief
  /// playing=false events from network glitches (e.g. ffurl_read) from
  /// incorrectly flipping the play/pause button.
  Timer? _ytPauseDebounce;

  @override
  Future<KaraokePlayerState> build() async {
    _disposed = false;
    _player = Player();
    videoController = VideoController(_player);
    _attachListeners();
    ref.onDispose(() {
      _disposed = true;
      _ytPauseDebounce?.cancel();
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
        if (playing) {
          // Cancel any pending debounced-pause when play resumes.
          _ytPauseDebounce?.cancel();
          return s.copyWith(status: PlayerStatus.playing);
        }
        // Don't overwrite 'idle' or 'loading' with 'paused'.
        if (s.isIdle || s.isLoading) return s;
        // Don't set paused while buffering.
        if (_player.state.buffering) return s;
        // For YouTube songs, debounce the paused state — network glitches
        // (e.g. ffurl_read) fire playing=false briefly but the player recovers
        // on its own. Only commit to paused after 600ms of sustained false.
        if (s.currentEntry?.songId == -1) {
          _ytPauseDebounce?.cancel();
          _ytPauseDebounce = Timer(const Duration(milliseconds: 600), () {
            if (!_player.state.playing && !_disposed) {
              _update((s2) {
                if (s2.isIdle || s2.isLoading) return s2;
                return s2.copyWith(status: PlayerStatus.paused);
              });
            }
          });
          return s; // keep current status while debouncing
        }
        return s.copyWith(status: PlayerStatus.paused);
      });
    }));
    // When buffering ends and the player is still supposed to be playing,
    // make sure our status reflects that.
    _subs.add(_player.stream.buffering.listen((buffering) {
      if (!buffering && _player.state.playing) {
        _update((s) => s.copyWith(status: PlayerStatus.playing));
      }
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
      // Ignore low-level FFmpeg/network warnings that don't stop playback.
      // These are noisy but non-fatal — the player recovers on its own.
      const ignoredPatterns = [
        'ffurl_read',
        'tcp:',
        'http:',
        'Connection reset',
        'Operation timed out',
        'AVERROR',
      ];
      if (ignoredPatterns.any((p) => err.contains(p))) return;

      final current = state.value?.currentEntry;
      // If a YouTube song fails, retry once with a freshly resolved stream URL.
      if (current != null && current.songId == -1 && current.song != null) {
        final video = YoutubeVideoResult(
          videoId: Uri.parse(current.song!.filePath).queryParameters['v'] ?? '',
          title: current.song!.title,
          channel: current.song!.artist ?? '',
          duration: null,
          thumbnailUrl: '',
        );
        if (video.videoId.isNotEmpty) {
          playYoutube(video, isRetry: true);
          return;
        }
      }
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

  /// Adds a YouTube video to the in-memory queue to be played after the
  /// current track finishes. Also pre-fetches the stream URL in the background
  /// so playback can start immediately when this song's turn arrives.
  void queueYoutube(YoutubeVideoResult video) {
    final item = UnifiedQueueItem(
      title: video.title,
      isYoutube: true,
      youtubeVideo: video,
    );
    _orderedQueue.add(item);
    _update((s) => s.copyWith(unifiedQueue: List.unmodifiable(_orderedQueue)));

    // Pre-fetch in the background — result stored in cache for use in playYoutube.
    ref
        .read(youtubeServiceProvider)
        .getBestStreamUrl(video.videoId)
        .then((url) {
      if (url != null) _streamUrlCache[video.videoId] = url;
    }).catchError((_) {
      // Ignore pre-fetch errors — playYoutube will retry on-demand.
    });
  }

  /// Enqueues a local song in the DB and registers it in the unified order
  /// list so YouTube + local songs advance in the order they were added.
  Future<void> queueLocal(Song song) async {
    if (song.id == null) return;
    final entry = await ref.read(queueRepositoryProvider).enqueue(song.id!);
    final item = UnifiedQueueItem(
      title: song.title,
      isYoutube: false,
      dbEntryId: entry.id,
    );
    _orderedQueue.add(item);
    _update((s) => s.copyWith(unifiedQueue: List.unmodifiable(_orderedQueue)));
    await ref.read(queueNotifierProvider.notifier).refresh();
  }

  /// Removes a pending queue item by its index in the unified queue.
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _orderedQueue.length) return;
    final item = _orderedQueue.removeAt(index);
    _update((s) => s.copyWith(unifiedQueue: List.unmodifiable(_orderedQueue)));
    // Evict any pre-fetched stream URL so we don't hold stale data.
    if (item.isYoutube && item.youtubeVideo != null) {
      _streamUrlCache.remove(item.youtubeVideo!.videoId);
    }
    if (!item.isYoutube && item.dbEntryId != null) {
      await ref.read(queueNotifierProvider.notifier).remove(item.dbEntryId!);
    }
  }

  /// Plays a YouTube video directly (no DB record — YouTube-only flow).
  /// [video] provides metadata; the stream URL is resolved on-the-fly.
  /// [_isRetry] is used internally to avoid infinite retry loops.
  Future<void> playYoutube(YoutubeVideoResult video,
      {bool isRetry = false}) async {
    if (_disposed) return;

    // Show loading state immediately with a synthetic entry so the UI
    // can display the title while the stream URL is being resolved.
    final syntheticSong = Song(
      id: null,
      title: video.title,
      artist: video.channel,
      filePath: video.watchUrl,
      hasVideo: true,
    );
    final syntheticEntry = QueueEntry(
      id: null,
      songId: -1,
      position: 0,
      status: QueueStatus.playing,
      song: syntheticSong,
    );

    _update((s) => s.copyWith(
          currentEntry: syntheticEntry,
          status: PlayerStatus.loading,
          position: Duration.zero,
          duration: Duration.zero,
          hasVideo: false,
        ));

    // Stop current playback immediately so the user sees the loading screen
    // right away instead of waiting for the stream URL to resolve.
    await _player.stop();

    try {
      // Use pre-fetched URL from cache if available — but skip cache on retry
      // since the cached URL may be expired (caused the error in the first place).
      final cached = isRetry ? null : _streamUrlCache.remove(video.videoId);
      final streamUrl = cached ??
          await ref
              .read(youtubeServiceProvider)
              .getBestStreamUrl(video.videoId);
      if (streamUrl == null) throw Exception('No playable stream found.');
      await _player.open(Media(streamUrl));
    } catch (e) {
      _update((s) => s.copyWith(
            status: PlayerStatus.error,
            errorMessage: e.toString(),
          ));
    }
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
    _update((s) => s.copyWith(
          volume: volume,
          // Track the last non-zero volume so we can restore it on unmute.
          lastVolume: volume > 0 ? volume : s.lastVolume,
        ));
  }

  Future<void> toggleMute() async {
    final s = state.value;
    if (s == null) return;
    if (s.volume > 0) {
      // Mute — remember current volume and set to 0.
      await _player.setVolume(0);
      _update((st) => st.copyWith(volume: 0, lastVolume: s.volume));
    } else {
      // Unmute — restore last known volume (at least 0.1).
      final restore = s.lastVolume > 0 ? s.lastVolume : 1.0;
      await _player.setVolume(restore * 100);
      _update((st) => st.copyWith(volume: restore));
    }
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
      // Pop the front of the unified ordered queue (preserves insertion order
      // across both local and YouTube items).
      while (_orderedQueue.isNotEmpty) {
        final next = _orderedQueue.removeAt(0);
        _update(
            (s) => s.copyWith(unifiedQueue: List.unmodifiable(_orderedQueue)));

        if (next.isYoutube && next.youtubeVideo != null) {
          // Keep _isAdvancing = true — playYoutube's _player.stop() must not
          // trigger _onTrackCompleted. The finally block releases it after
          // playYoutube returns.
          await playYoutube(next.youtubeVideo!);
          return;
        } else if (!next.isYoutube && next.dbEntryId != null) {
          // Local song — look it up from DB.
          final queue = await ref.read(queueRepositoryProvider).getActive();
          final entry = queue
              .where((e) => e.id == next.dbEntryId && e.id != doneEntryId)
              .firstOrNull;
          if (entry != null) {
            await playEntry(entry);
            await ref.read(queueNotifierProvider.notifier).refresh();
            return;
          }
          // Entry was already done/removed — skip to next in order.
          continue;
        }
      }

      // Ordered queue exhausted — fall back to any remaining DB entries
      // (e.g. songs queued before this session or by external means).
      final queue = await ref.read(queueRepositoryProvider).getActive();
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
    // Only update play count for real local songs (YouTube entries have songId = -1).
    if (current.songId != -1) {
      await ref.read(songRepositoryProvider).incrementPlayCount(current.songId);
    }
    await _advanceQueue(doneEntryId: current.id);
  }

  void _update(KaraokePlayerState Function(KaraokePlayerState) fn) {
    if (state.hasValue) state = AsyncData(fn(state.value!));
  }
}

final playerProvider =
    AsyncNotifierProvider<PlayerNotifier, KaraokePlayerState>(
        PlayerNotifier.new);
