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
    final nextPos = ((maxPos.first['mp'] as int?) ?? -1) + 1;

    final entry = QueueEntry(songId: songId, position: nextPos);
    final id = await _db.db.insert('queue_entries', entry.toMap());
    return entry.copyWith(id: id);
  }

  Future<void> markPlaying(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'playing', 'started_at': DateTime.now().toIso8601String()},
      where: 'id = ?', whereArgs: [id],
    );
  }

  Future<void> markDone(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'done', 'finished_at': DateTime.now().toIso8601String()},
      where: 'id = ?', whereArgs: [id],
    );
  }

  Future<void> markSkipped(int id) async {
    await _db.db.update(
      'queue_entries',
      {'status': 'skipped', 'finished_at': DateTime.now().toIso8601String()},
      where: 'id = ?', whereArgs: [id],
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
    final song = Song(
      id: row['song_id'] as int,
      title: row['song_title'] as String,
      artist: row['song_artist'] as String?,
      filePath: row['song_file_path'] as String,
      folderName: row['song_folder_name'] as String?,
      durationMs: row['song_duration_ms'] as int?,
      playCount: row['song_play_count'] as int? ?? 0,
      addedAt: DateTime.parse(row['song_added_at'] as String),
    );
    return QueueEntry.fromMap(row).copyWith(song: song);
  }
}

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(DatabaseHelper.instance),
);
