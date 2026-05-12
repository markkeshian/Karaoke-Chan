// lib/features/library/data/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';

class SongRepository {
  SongRepository(this._db);

  final DatabaseHelper _db;

  Future<List<Song>> getAll({String? search}) async {
    if (search != null && search.trim().isNotEmpty) {
      final query = '%${search.trim()}%';
      final rows = await _db.db.query(
        'songs',
        where: 'title LIKE ? OR artist LIKE ? OR folder_name LIKE ?',
        whereArgs: [query, query, query],
        orderBy: 'title ASC',
      );
      return rows.map(Song.fromMap).toList();
    }
    final rows = await _db.db.query('songs', orderBy: 'title ASC');
    return rows.map(Song.fromMap).toList();
  }

  Future<Song?> getById(int id) async {
    final rows = await _db.db.query('songs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Song.fromMap(rows.first);
  }

  Future<Song> insert(Song song) async {
    // Use INSERT OR REPLACE to handle duplicates (same file_path)
    final id = await _db.db.rawInsert(
      '''INSERT OR REPLACE INTO songs
         (title, artist, file_path, folder_name, duration_ms, cover_art_path,
          play_count, last_played_at, has_video, added_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        song.title,
        song.artist,
        song.filePath,
        song.folderName,
        song.durationMs,
        song.coverArtPath,
        song.playCount,
        song.lastPlayedAt?.toIso8601String(),
        song.hasVideo ? 1 : 0,
        song.addedAt.toIso8601String(),
      ],
    );
    return song.copyWith(id: id);
  }

  /// Inserts a list of songs in a single transaction — much faster than
  /// calling [insert] in a loop for large libraries.
  Future<List<Song>> insertAll(List<Song> songs) async {
    final List<Song> inserted = [];
    await _db.db.transaction((txn) async {
      for (final song in songs) {
        final id = await txn.rawInsert(
          '''INSERT OR REPLACE INTO songs
             (title, artist, file_path, folder_name, duration_ms, cover_art_path,
              play_count, last_played_at, has_video, added_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            song.title,
            song.artist,
            song.filePath,
            song.folderName,
            song.durationMs,
            song.coverArtPath,
            song.playCount,
            song.lastPlayedAt?.toIso8601String(),
            song.hasVideo ? 1 : 0,
            song.addedAt.toIso8601String(),
          ],
        );
        inserted.add(song.copyWith(id: id));
      }
    });
    return inserted;
  }

  Future<void> update(Song song) async {
    await _db.db.update(
      'songs',
      song.toMap(),
      where: 'id = ?',
      whereArgs: [song.id],
    );
  }

  Future<void> delete(int id) async {
    await _db.db.delete('songs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByPath(String filePath) async {
    await _db.db.delete('songs', where: 'file_path = ?', whereArgs: [filePath]);
  }

  /// Remove all songs whose file path starts with [rootPath]
  /// (i.e. everything from a given scanned folder).
  Future<void> deleteByFolderRoot(String rootPath) async {
    await _db.db.delete(
      'songs',
      where: "file_path LIKE ?",
      whereArgs: ['$rootPath%'],
    );
  }

  Future<void> incrementPlayCount(int songId) async {
    await _db.db.rawUpdate(
      '''UPDATE songs
         SET play_count = play_count + 1,
             last_played_at = datetime('now')
         WHERE id = ?''',
      [songId],
    );
  }

  Future<List<Song>> getTopPlayed({int limit = 10}) async {
    final rows = await _db.db.query(
      'songs',
      orderBy: 'play_count DESC',
      limit: limit,
    );
    return rows.map(Song.fromMap).toList();
  }

  /// Returns groups of songs that share the same title (case-insensitive)
  /// but have different file paths — i.e. potential duplicates / alternate versions.
  /// Only groups with 2 or more entries are returned.
  Future<Map<String, List<Song>>> getDuplicates() async {
    final rows = await _db.db.rawQuery('''
      SELECT * FROM songs
      WHERE LOWER(title) IN (
        SELECT LOWER(title) FROM songs GROUP BY LOWER(title) HAVING COUNT(*) > 1
      )
      ORDER BY LOWER(title) ASC, added_at ASC
    ''');
    final songs = rows.map(Song.fromMap).toList();
    final Map<String, List<Song>> groups = {};
    for (final song in songs) {
      final key = song.title.toLowerCase();
      groups.putIfAbsent(key, () => []).add(song);
    }
    return groups;
  }
}

final songRepositoryProvider = Provider<SongRepository>(
  (ref) => SongRepository(DatabaseHelper.instance),
);

final songsProvider = FutureProvider.family<List<Song>, String?>((ref, search) {
  return ref.watch(songRepositoryProvider).getAll(search: search);
});

/// Watches for songs that share the same title (case-insensitive) but live at
/// different file paths.  Invalidated whenever [songRepositoryProvider] is.
final duplicatesProvider = FutureProvider<Map<String, List<Song>>>((ref) {
  return ref.watch(songRepositoryProvider).getDuplicates();
});
