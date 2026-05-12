// test/queue_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';
import 'helpers/test_database.dart';

void main() {
  late SongRepository songRepo;
  late QueueRepository queueRepo;

  /// Helper: insert a song and return it with its db id.
  Future<Song> addSong({String title = 'Song', String filePath = '/s.mp4'}) =>
      songRepo.insert(Song(title: title, filePath: filePath));

  setUp(() async {
    final db = await openTestDatabase();
    songRepo = SongRepository(db);
    queueRepo = QueueRepository(db);
  });

  tearDown(() async {
    await queueRepo.clearAll();
    final songs = await songRepo.getAll();
    for (final s in songs) {
      if (s.id != null) await songRepo.delete(s.id!);
    }
  });

  group('QueueRepository', () {
    test('enqueue adds entry and assigns id', () async {
      final song = await addSong();
      final entry = await queueRepo.enqueue(song.id!);

      expect(entry.id, isNotNull);
      expect(entry.songId, song.id);
      expect(entry.status, QueueStatus.waiting);
      expect(entry.position, 0);
    });

    test('enqueue increments position for each new entry', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      final s3 = await addSong(title: 'C', filePath: '/c.mp4');

      final e1 = await queueRepo.enqueue(s1.id!);
      final e2 = await queueRepo.enqueue(s2.id!);
      final e3 = await queueRepo.enqueue(s3.id!);

      expect(e1.position, 0);
      expect(e2.position, 1);
      expect(e3.position, 2);
    });

    test('getActive returns waiting and playing entries with joined song', () async {
      final song = await addSong();
      await queueRepo.enqueue(song.id!);

      final active = await queueRepo.getActive();
      expect(active, hasLength(1));
      expect(active.first.song, isNotNull);
      expect(active.first.song!.title, song.title);
    });

    test('getActive excludes done and skipped entries', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      final s3 = await addSong(title: 'C', filePath: '/c.mp4');

      final e1 = await queueRepo.enqueue(s1.id!);
      final e2 = await queueRepo.enqueue(s2.id!);
      final e3 = await queueRepo.enqueue(s3.id!);

      await queueRepo.markDone(e1.id!);
      await queueRepo.markSkipped(e2.id!);

      final active = await queueRepo.getActive();
      expect(active, hasLength(1));
      expect(active.first.id, e3.id);
    });

    test('getActive returns entries sorted by position', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      await queueRepo.enqueue(s1.id!);
      await queueRepo.enqueue(s2.id!);

      final active = await queueRepo.getActive();
      expect(active[0].position, lessThan(active[1].position));
    });

    test('markPlaying updates status to playing', () async {
      final song = await addSong();
      final entry = await queueRepo.enqueue(song.id!);
      await queueRepo.markPlaying(entry.id!);

      final current = await queueRepo.getCurrentlyPlaying();
      expect(current, isNotNull);
      expect(current!.status, QueueStatus.playing);
      expect(current.startedAt, isNotNull);
    });

    test('markDone updates status to done', () async {
      final song = await addSong();
      final entry = await queueRepo.enqueue(song.id!);
      await queueRepo.markPlaying(entry.id!);
      await queueRepo.markDone(entry.id!);

      final active = await queueRepo.getActive();
      expect(active, isEmpty);
    });

    test('markSkipped updates status to skipped', () async {
      final song = await addSong();
      final entry = await queueRepo.enqueue(song.id!);
      await queueRepo.markSkipped(entry.id!);

      final active = await queueRepo.getActive();
      expect(active, isEmpty);
    });

    test('getCurrentlyPlaying returns null when nothing playing', () async {
      final song = await addSong();
      await queueRepo.enqueue(song.id!);

      final current = await queueRepo.getCurrentlyPlaying();
      expect(current, isNull);
    });

    test('remove deletes entry and compacts positions', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      final s3 = await addSong(title: 'C', filePath: '/c.mp4');

      final e1 = await queueRepo.enqueue(s1.id!);
      await queueRepo.enqueue(s2.id!);
      await queueRepo.enqueue(s3.id!);

      await queueRepo.remove(e1.id!);
      final active = await queueRepo.getActive();

      expect(active, hasLength(2));
      // positions should be compacted to 0, 1
      expect(active[0].position, 0);
      expect(active[1].position, 1);
    });

    test('reorder updates positions correctly', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      final s3 = await addSong(title: 'C', filePath: '/c.mp4');

      final e1 = await queueRepo.enqueue(s1.id!);
      final e2 = await queueRepo.enqueue(s2.id!);
      final e3 = await queueRepo.enqueue(s3.id!);

      // Reverse the order
      await queueRepo.reorder([e3.id!, e2.id!, e1.id!]);

      final active = await queueRepo.getActive();
      expect(active[0].id, e3.id);
      expect(active[1].id, e2.id);
      expect(active[2].id, e1.id);
    });

    test('clearAll removes all entries', () async {
      final s1 = await addSong(title: 'A', filePath: '/a.mp4');
      final s2 = await addSong(title: 'B', filePath: '/b.mp4');
      await queueRepo.enqueue(s1.id!);
      await queueRepo.enqueue(s2.id!);

      await queueRepo.clearAll();
      final active = await queueRepo.getActive();
      expect(active, isEmpty);
    });
  });
}

