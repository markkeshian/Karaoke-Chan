// lib/features/player/data/player_state.dart
import '../../queue/data/queue_entry_model.dart';

enum PlayerStatus { idle, loading, playing, paused, error }

class KaraokePlayerState {
  const KaraokePlayerState({
    this.currentEntry,
    this.status = PlayerStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.errorMessage,
  });

  final QueueEntry? currentEntry;
  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? errorMessage;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isPaused => status == PlayerStatus.paused;
  bool get isIdle => status == PlayerStatus.idle;
  bool get hasError => status == PlayerStatus.error;
  bool get hasVideo => false; // updated by PlayerNotifier when video track detected

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
    String? errorMessage,
    bool clearEntry = false,
  }) {
    return KaraokePlayerState(
      currentEntry: clearEntry ? null : (currentEntry ?? this.currentEntry),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
