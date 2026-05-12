// test/queue_entry_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';

void main() {
  group('QueueEntry model', () {
    final baseMap = {
      'id': 10,
      'song_id': 1,
      'position': 0,
      'status': 'waiting',
      'added_at': '2026-01-01T12:00:00.000',
      'started_at': null,
      'finished_at': null,
    };

    test('fromMap parses all fields', () {
      final entry = QueueEntry.fromMap(baseMap);

      expect(entry.id, 10);
      expect(entry.songId, 1);
      expect(entry.position, 0);
      expect(entry.status, QueueStatus.waiting);
      expect(entry.addedAt, DateTime.parse('2026-01-01T12:00:00.000'));
      expect(entry.startedAt, isNull);
      expect(entry.finishedAt, isNull);
    });

    test('fromMap parses playing status', () {
      final entry = QueueEntry.fromMap({...baseMap, 'status': 'playing'});
      expect(entry.status, QueueStatus.playing);
    });

    test('fromMap parses done status', () {
      final entry = QueueEntry.fromMap({...baseMap, 'status': 'done'});
      expect(entry.status, QueueStatus.done);
    });

    test('fromMap parses skipped status', () {
      final entry = QueueEntry.fromMap({...baseMap, 'status': 'skipped'});
      expect(entry.status, QueueStatus.skipped);
    });

    test('fromMap falls back to waiting for unknown status', () {
      final entry = QueueEntry.fromMap({...baseMap, 'status': 'unknown_status'});
      expect(entry.status, QueueStatus.waiting);
    });

    test('fromMap parses started_at and finished_at when set', () {
      final map = {
        ...baseMap,
        'status': 'done',
        'started_at': '2026-01-01T12:01:00.000',
        'finished_at': '2026-01-01T12:05:00.000',
      };
      final entry = QueueEntry.fromMap(map);
      expect(entry.startedAt, DateTime.parse('2026-01-01T12:01:00.000'));
      expect(entry.finishedAt, DateTime.parse('2026-01-01T12:05:00.000'));
    });

    test('toMap round-trips back via fromMap', () {
      final entry = QueueEntry.fromMap({
        ...baseMap,
        'status': 'playing',
        'started_at': '2026-01-01T12:01:00.000',
      });
      final map = entry.toMap();
      final entry2 = QueueEntry.fromMap(map);

      expect(entry2.id, entry.id);
      expect(entry2.songId, entry.songId);
      expect(entry2.position, entry.position);
      expect(entry2.status, entry.status);
      expect(entry2.startedAt, entry.startedAt);
    });

    test('toMap excludes id when null', () {
      final entry = QueueEntry(songId: 1, position: 0);
      final map = entry.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith overrides individual fields', () {
      final entry = QueueEntry.fromMap(baseMap);
      final updated = entry.copyWith(status: QueueStatus.playing, position: 5);

      expect(updated.status, QueueStatus.playing);
      expect(updated.position, 5);
      expect(updated.songId, entry.songId); // unchanged
    });

    test('copyWith can attach a Song', () {
      final entry = QueueEntry.fromMap(baseMap);
      final song = Song(id: 1, title: 'Test Song', filePath: '/test.cdg');
      final withSong = entry.copyWith(song: song);

      expect(withSong.song, song);
    });

    test('equality is based on id', () {
      final a = QueueEntry.fromMap(baseMap);
      final b = a.copyWith(position: 99);
      expect(a, equals(b));
    });

    test('entries with different ids are not equal', () {
      final a = QueueEntry.fromMap(baseMap);
      final b = QueueEntry.fromMap({...baseMap, 'id': 20});
      expect(a, isNot(equals(b)));
    });

    test('addedAt defaults to now when not provided', () {
      final before = DateTime.now();
      final entry = QueueEntry(songId: 1, position: 0);
      final after = DateTime.now();

      expect(entry.addedAt.isAfter(before) || entry.addedAt.isAtSameMomentAs(before), isTrue);
      expect(entry.addedAt.isBefore(after) || entry.addedAt.isAtSameMomentAs(after), isTrue);
    });
  });
}

