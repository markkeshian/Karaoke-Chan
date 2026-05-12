// test/helpers/test_database.dart
import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh in-memory SQLite database with the full app schema
/// and injects it into [DatabaseHelper.instance] for testing.
/// Call this in [setUp] — a new, isolated database is created each time.
Future<DatabaseHelper> openTestDatabase() async {
  sqfliteFfiInit();

  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT,
            file_path TEXT NOT NULL UNIQUE,
            folder_name TEXT,
            duration_ms INTEGER,
            cover_art_path TEXT,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at TEXT,
            added_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');

        await db.execute('''
          CREATE TABLE queue_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            song_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'waiting',
            added_at TEXT NOT NULL DEFAULT (datetime('now')),
            started_at TEXT,
            finished_at TEXT,
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
          )
        ''');
      },
    ),
  );

  DatabaseHelper.instance.injectForTesting(db);
  return DatabaseHelper.instance;
}



