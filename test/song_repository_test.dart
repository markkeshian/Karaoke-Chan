// test/song_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'helpers/test_database.dart';

void main() {
  late SongRepository repo;

  setUp(() async {
    final db = await openTestDatabase();
    repo = SongRepository(db);
  });

  tearDown(() async {
    // Wipe songs table between tests
    await repo.getAll().then((songs) async {
      for (final s in songs) {
        if (s.id != null) await repo.delete(s.id!);
      }
    });
  });

  Song song0({
    String title = 'Test Song',
    String? artist,
    String filePath = '/music/test.mp4',
  }) =>
      Song(title: title, artist: artist, filePath: filePath);

  group('SongRepository', () {
    test('insert returns song with assigned id', () async {
      final song = await repo.insert(song0());
      expect(song.id, isNotNull);
      expect(song.id, greaterThan(0));
      expect(song.title, 'Test Song');
    });

    test('getAll returns all inserted songs', () async {
      await repo.insert(song0(title: 'A', filePath: '/a.mp4'));
      await repo.insert(song0(title: 'B', filePath: '/b.mp4'));

      final songs = await repo.getAll();
      expect(songs, hasLength(2));
    });

    test('getAll returns songs sorted by title ASC', () async {
      await repo.insert(song0(title: 'Zebra', filePath: '/z.mp4'));
      await repo.insert(song0(title: 'Apple', filePath: '/a.mp4'));

      final songs = await repo.getAll();
      expect(songs[0].title, 'Apple');
      expect(songs[1].title, 'Zebra');
    });

    test('getAll filters by title search', () async {
      await repo.insert(song0(title: 'Rock Anthem', filePath: '/rock.mp4'));
      await repo.insert(song0(title: 'Pop Hits', filePath: '/pop.mp4'));

      final results = await repo.getAll(search: 'Rock');
      expect(results, hasLength(1));
      expect(results.first.title, 'Rock Anthem');
    });

    test('getAll filters by artist search', () async {
      await repo
          .insert(song0(title: 'Song', artist: 'Queen', filePath: '/q.mp4'));
      await repo
          .insert(song0(title: 'Another', artist: 'Adele', filePath: '/a.mp4'));

      final results = await repo.getAll(search: 'Queen');
      expect(results, hasLength(1));
      expect(results.first.artist, 'Queen');
    });

    test('getAll is case-insensitive in search', () async {
      await repo.insert(song0(title: 'Summer Hits', filePath: '/s.mp4'));

      expect(await repo.getAll(search: 'summer'), hasLength(1));
      expect(await repo.getAll(search: 'SUMMER'), hasLength(1));
      expect(await repo.getAll(search: 'SuMmEr'), hasLength(1));
    });

    test('getById returns correct song', () async {
      final inserted = await repo.insert(song0());
      final found = await repo.getById(inserted.id!);
      expect(found, isNotNull);
      expect(found!.title, inserted.title);
    });

    test('getById returns null for missing id', () async {
      final found = await repo.getById(9999);
      expect(found, isNull);
    });

    test('delete removes song from db', () async {
      final song = await repo.insert(song0());
      await repo.delete(song.id!);

      final found = await repo.getById(song.id!);
      expect(found, isNull);
    });

    test('deleteByPath removes by file path', () async {
      await repo.insert(song0(filePath: '/target.mp4'));
      await repo.deleteByPath('/target.mp4');

      final songs = await repo.getAll();
      expect(songs.where((s) => s.filePath == '/target.mp4'), isEmpty);
    });

    test('deleteByFolderRoot removes all matching paths', () async {
      await repo.insert(song0(title: 'A', filePath: '/music/pop/a.mp4'));
      await repo.insert(song0(title: 'B', filePath: '/music/rock/b.mp4'));
      await repo.insert(song0(title: 'C', filePath: '/other/c.mp4'));

      await repo.deleteByFolderRoot('/music');

      final songs = await repo.getAll();
      expect(songs, hasLength(1));
      expect(songs.first.title, 'C');
    });

    test('incrementPlayCount increases play_count by one', () async {
      final song = await repo.insert(song0());
      expect(song.playCount, 0);

      await repo.incrementPlayCount(song.id!);
      final updated = await repo.getById(song.id!);
      expect(updated!.playCount, 1);

      await repo.incrementPlayCount(song.id!);
      final updated2 = await repo.getById(song.id!);
      expect(updated2!.playCount, 2);
    });

    test('getTopPlayed returns songs ordered by play count', () async {
      await repo.insert(song0(title: 'Rarely Played', filePath: '/rare.mp4'));
      final b = await repo
          .insert(song0(title: 'Often Played', filePath: '/often.mp4'));

      await repo.incrementPlayCount(b.id!);
      await repo.incrementPlayCount(b.id!);
      await repo.incrementPlayCount(b.id!);

      final top = await repo.getTopPlayed(limit: 2);
      expect(top.first.title, 'Often Played');
    });

    test('insert with same file_path replaces existing song', () async {
      await repo.insert(song0(title: 'Original'));
      await repo.insert(song0(title: 'Replacement')); // same filePath

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.title, 'Replacement');
    });

    test('update changes song fields', () async {
      final song = await repo.insert(song0(title: 'Old Title'));
      await repo.update(song.copyWith(title: 'New Title'));

      final updated = await repo.getById(song.id!);
      expect(updated!.title, 'New Title');
    });
  });
}
