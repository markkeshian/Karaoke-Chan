// test/player_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/player/data/player_state.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';

void main() {
  group('KaraokePlayerState', () {
    const defaultState = KaraokePlayerState();

    test('default state values', () {
      expect(defaultState.status, PlayerStatus.idle);
      expect(defaultState.position, Duration.zero);
      expect(defaultState.duration, Duration.zero);
      expect(defaultState.volume, 1.0);
      expect(defaultState.currentEntry, isNull);
      expect(defaultState.errorMessage, isNull);
    });

    test('isIdle is true by default', () {
      expect(defaultState.isIdle, isTrue);
      expect(defaultState.isPlaying, isFalse);
      expect(defaultState.isPaused, isFalse);
      expect(defaultState.hasError, isFalse);
    });

    test('isPlaying reflects playing status', () {
      final s = defaultState.copyWith(status: PlayerStatus.playing);
      expect(s.isPlaying, isTrue);
      expect(s.isIdle, isFalse);
    });

    test('isPaused reflects paused status', () {
      final s = defaultState.copyWith(status: PlayerStatus.paused);
      expect(s.isPaused, isTrue);
    });

    test('hasError reflects error status', () {
      final s = defaultState.copyWith(
          status: PlayerStatus.error, errorMessage: 'File not found');
      expect(s.hasError, isTrue);
      expect(s.errorMessage, 'File not found');
    });

    group('progressFraction', () {
      test('returns 0.0 when duration is zero', () {
        expect(defaultState.progressFraction, 0.0);
      });

      test('returns correct fraction mid-way', () {
        final s = defaultState.copyWith(
          duration: const Duration(minutes: 4),
          position: const Duration(minutes: 2),
        );
        expect(s.progressFraction, closeTo(0.5, 0.001));
      });

      test('clamps to 1.0 when position exceeds duration', () {
        final s = defaultState.copyWith(
          duration: const Duration(seconds: 10),
          position: const Duration(seconds: 15),
        );
        expect(s.progressFraction, 1.0);
      });

      test('returns 0.0 at start', () {
        final s = defaultState.copyWith(
          duration: const Duration(minutes: 3),
          position: Duration.zero,
        );
        expect(s.progressFraction, 0.0);
      });

      test('returns 1.0 at end', () {
        final s = defaultState.copyWith(
          duration: const Duration(minutes: 3),
          position: const Duration(minutes: 3),
        );
        expect(s.progressFraction, closeTo(1.0, 0.001));
      });
    });

    test('copyWith preserves unchanged fields', () {
      final song = Song(id: 1, title: 'Test', filePath: '/t.cdg');
      final entry = QueueEntry(id: 1, songId: 1, position: 0, song: song);

      final s = defaultState.copyWith(
        currentEntry: entry,
        status: PlayerStatus.playing,
        volume: 0.8,
      );

      expect(s.currentEntry, entry);
      expect(s.status, PlayerStatus.playing);
      expect(s.volume, 0.8);
      // position/duration unchanged
      expect(s.position, Duration.zero);
      expect(s.duration, Duration.zero);
    });

    test('copyWith clearEntry removes currentEntry', () {
      final song = Song(id: 1, title: 'Test', filePath: '/t.cdg');
      final entry = QueueEntry(id: 1, songId: 1, position: 0, song: song);
      final s = defaultState.copyWith(currentEntry: entry);
      final cleared = s.copyWith(clearEntry: true);
      expect(cleared.currentEntry, isNull);
    });

    test('hasVideo is always false (not yet implemented)', () {
      expect(defaultState.hasVideo, isFalse);
    });
  });
}

