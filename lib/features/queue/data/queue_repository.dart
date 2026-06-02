// lib/features/queue/data/queue_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';

class QueueRepository {
  QueueRepository(this._db);

  final DatabaseHelper _db;

  Future<List<QueueEntry>> getActive() async {
    final rows = await _db.db.rawQuery('''
      SELECT
        q.*,
        s.title  AS song_title,
        s.artist AS song_artist,
        s.file_path AS song_file_path,
        s.folder_name AS song_folder_name,
        s.duration_ms AS song_duration_ms,
        s.play_count  AS song_play_count,
        s.added_at    AS song_added_at
      FROM queue_entries q
      JOIN songs s ON q.song_id = s.id
      WHERE q.status IN ('waiting','playing')
      ORDER BY q.position ASC
    ''');
    return rows.map(_mapRow).toList();
  }

  Future<QueueEntry?> getCurrentlyPlaying() async {
    final rows = await _db.db.rawQuery('''
      SELECT q.*,
        s.title AS song_title, s.artist AS song_artist,
        s.file_path AS song_file_path, s.folder_name AS song_folder_name,
        s.duration_ms AS song_duration_ms, s.play_count AS song_play_count,
        s.added_at AS song_added_at
      FROM queue_entries q
      JOIN songs s ON q.song_id = s.id
      WHERE q.status = 'playing'
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    return _mapRow(rows.first);
  }

  Future<QueueEntry> enqueue(int songId) async {
    final maxPos = await _db.db.rawQuery(
      "SELECT MAX(position) AS mp FROM queue_entries WHERE status IN ('waiting','playing')",
    );
    // Defensive cast: some sqflite backends return numerics as `num`/`BigInt`
    // rather than `int`, which would throw on a direct `as int?` cast.
    final rawMp = maxPos.isNotEmpty ? maxPos.first['mp'] : null;
    final nextPos = ((rawMp is num) ? rawMp.toInt() : -1) + 1;

    final entry = QueueEntry(songId: songId, position: nextPos);
    final id = await _db.db.insert('queue_entries', entry.toMap());
    return entry.copyWith(id: id);
  }

  Future<void> markPlaying(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'playing', 'started_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markDone(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'done', 'finished_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSkipped(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'skipped', 'finished_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remove(int id) async {
    await _db.db.delete('queue_entries', where: 'id = ?', whereArgs: [id]);
    await _reorder();
  }

  Future<void> reorder(List<int> orderedIds) async {
    final batch = _db.db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('queue_entries', {'position': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearAll() async {
    await _db.db.delete('queue_entries');
  }

  /// Called on app startup: any entry left in 'playing' state is from a
  /// previous session (app was closed mid-song). Reset them to 'waiting' so
  /// they can be played again, rather than showing as phantom queue items.
  Future<void> resetStalePlaying() async {
    await _db.db.update(
      'queue_entries',
      {'status': 'waiting', 'started_at': null},
      where: "status = 'playing'",
    );
  }

  Future<void> _reorder() async {
    final rows = await _db.db.query(
      'queue_entries',
      where: "status IN ('waiting','playing')",
      orderBy: 'position ASC',
      columns: ['id'],
    );
    final batch = _db.db.batch();
    for (var i = 0; i < rows.length; i++) {
      batch.update('queue_entries', {'position': i},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
    await batch.commit(noResult: true);
  }

  QueueEntry _mapRow(Map<String, dynamic> row) {
    // Defensive numeric casts: some sqflite backends return ints as `num`.
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    final song = Song(
      id: asInt(row['song_id']) ?? 0,
      title: row['song_title'] as String? ?? '',
      artist: row['song_artist'] as String?,
      filePath: row['song_file_path'] as String? ?? '',
      folderName: row['song_folder_name'] as String?,
      durationMs: asInt(row['song_duration_ms']),
      playCount: asInt(row['song_play_count']) ?? 0,
      addedAt: _parseDateOrNow(row['song_added_at']),
    );
    return QueueEntry.fromMap(row).copyWith(song: song);
  }

  static DateTime _parseDateOrNow(Object? v) {
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        // Fall through on malformed date strings.
      }
    }
    return DateTime.now();
  }
}

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(DatabaseHelper.instance),
);
