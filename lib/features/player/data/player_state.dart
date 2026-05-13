// lib/features/player/data/player_state.dart
import 'package:karaoke_chan/core/services/youtube_service.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';

enum PlayerStatus { idle, loading, playing, paused, error }

/// A single item in the unified pending queue.
/// Carries display info + enough data for the player to start playback.
class UnifiedQueueItem {
  const UnifiedQueueItem({
    required this.title,
    required this.isYoutube,
    this.dbEntryId,
    this.youtubeVideo,
  });

  final String title;
  final bool isYoutube;

  /// Non-null for local songs — the DB queue entry ID used for removal.
  final int? dbEntryId;

  /// Non-null for YouTube songs — the full result object used for playback.
  final YoutubeVideoResult? youtubeVideo;
}

class KaraokePlayerState {
  const KaraokePlayerState({
    this.currentEntry,
    this.status = PlayerStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.lastVolume = 1.0,
    this.errorMessage,
    this.hasVideo = false,
    List<UnifiedQueueItem>? unifiedQueue,
  }) : _unifiedQueue = unifiedQueue;

  final QueueEntry? currentEntry;
  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final double volume;

  /// The last non-zero volume — used to restore when unmuting.
  final double lastVolume;
  final String? errorMessage;
  final bool hasVideo;

  // Nullable backing field — hot-reload safe.
  final List<UnifiedQueueItem>? _unifiedQueue;

  /// Pending queue items in insertion order (local + YouTube interleaved).
  List<UnifiedQueueItem> get unifiedQueue =>
      _unifiedQueue ?? const <UnifiedQueueItem>[];

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isPaused => status == PlayerStatus.paused;
  bool get isIdle => status == PlayerStatus.idle;
  bool get isLoading => status == PlayerStatus.loading;
  bool get hasError => status == PlayerStatus.error;

  double get progressFraction {
    if (duration == Duration.zero) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  KaraokePlayerState copyWith({
    QueueEntry? currentEntry,
    PlayerStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    double? lastVolume,
    String? errorMessage,
    bool? hasVideo,
    List<UnifiedQueueItem>? unifiedQueue,
    bool clearEntry = false,
    bool clearError = false,
  }) {
    return KaraokePlayerState(
      currentEntry: clearEntry ? null : (currentEntry ?? this.currentEntry),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      lastVolume: lastVolume ?? this.lastVolume,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hasVideo: hasVideo ?? this.hasVideo,
      unifiedQueue: unifiedQueue ?? this.unifiedQueue,
    );
  }
}
