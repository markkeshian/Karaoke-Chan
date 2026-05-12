// test/song_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';

void main() {
  group('Song model', () {
    final baseMap = {
      'id': 1,
      'title': 'Never Gonna Give You Up',
      'artist': 'Rick Astley',
      'file_path': '/music/rick.cdg',
      'folder_name': 'music',
      'duration_ms': 213000,
      'cover_art_path': null,
      'play_count': 3,
      'last_played_at': '2026-01-10T20:00:00.000',
      'added_at': '2026-01-01T10:00:00.000',
    };

    test('fromMap parses all fields', () {
      final song = Song.fromMap(baseMap);

      expect(song.id, 1);
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.artist, 'Rick Astley');
      expect(song.filePath, '/music/rick.cdg');
      expect(song.folderName, 'music');
      expect(song.durationMs, 213000);
      expect(song.coverArtPath, isNull);
      expect(song.playCount, 3);
      expect(song.lastPlayedAt, DateTime.parse('2026-01-10T20:00:00.000'));
      expect(song.addedAt, DateTime.parse('2026-01-01T10:00:00.000'));
    });

    test('toMap round-trips back to fromMap', () {
      final song = Song.fromMap(baseMap);
      final map = song.toMap();
      final song2 = Song.fromMap({...map, 'added_at': map['added_at']});

      expect(song2.id, song.id);
      expect(song2.title, song.title);
      expect(song2.artist, song.artist);
      expect(song2.filePath, song.filePath);
      expect(song2.durationMs, song.durationMs);
      expect(song2.playCount, song.playCount);
    });

    test('toMap excludes id when null', () {
      final song = Song(title: 'Test', filePath: '/test.cdg');
      final map = song.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith overrides individual fields', () {
      final song = Song.fromMap(baseMap);
      final updated = song.copyWith(title: 'Updated', playCount: 10);

      expect(updated.title, 'Updated');
      expect(updated.playCount, 10);
      // unchanged fields preserved
      expect(updated.artist, song.artist);
      expect(updated.filePath, song.filePath);
    });

    test('displayDuration formats mm:ss correctly', () {
      final song = Song(title: 'T', filePath: '/t.cdg', durationMs: 213000); // 3:33
      expect(song.displayDuration, '03:33');
    });

    test('displayDuration returns --:-- when null', () {
      final song = Song(title: 'T', filePath: '/t.cdg');
      expect(song.displayDuration, '--:--');
    });

    test('displayDuration pads seconds correctly', () {
      final song = Song(title: 'T', filePath: '/t.cdg', durationMs: 65000); // 1:05
      expect(song.displayDuration, '01:05');
    });

    test('equality is based on id', () {
      final a = Song.fromMap(baseMap);
      final b = a.copyWith(title: 'Different Title');
      expect(a, equals(b));
    });

    test('songs with different ids are not equal', () {
      final a = Song.fromMap(baseMap);
      final b = Song.fromMap({...baseMap, 'id': 2});
      expect(a, isNot(equals(b)));
    });

    test('addedAt defaults to now when not provided', () {
      final before = DateTime.now();
      final song = Song(title: 'T', filePath: '/t.cdg');
      final after = DateTime.now();

      expect(song.addedAt.isAfter(before) || song.addedAt.isAtSameMomentAs(before), isTrue);
      expect(song.addedAt.isBefore(after) || song.addedAt.isAtSameMomentAs(after), isTrue);
    });

    test('fromMap handles null optional fields gracefully', () {
      final map = {
        'id': null,
        'title': 'Minimal Song',
        'artist': null,
        'file_path': '/min.cdg',
        'folder_name': null,
        'duration_ms': null,
        'cover_art_path': null,
        'play_count': null,
        'last_played_at': null,
        'added_at': '2026-05-01T00:00:00.000',
      };
      final song = Song.fromMap(map);
      expect(song.id, isNull);
      expect(song.artist, isNull);
      expect(song.durationMs, isNull);
      expect(song.playCount, 0); // defaults to 0
    });
  });
}

