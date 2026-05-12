// lib/core/database/database_helper.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;
  // Prevents concurrent calls to init() from opening the database twice.
  static Completer<void>? _initCompleter;

  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  Future<void> init() async {
    if (_db != null) return;

    // If another init() is already in progress, wait for it to finish.
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();

    try {
      // Use FFI for desktop platforms
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'karaoke_chan.db');

      _db = await openDatabase(
        path,
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
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
        has_video INTEGER NOT NULL DEFAULT 0,
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

    await db
        .execute('CREATE INDEX idx_queue_position ON queue_entries(position)');
    await db.execute('CREATE INDEX idx_queue_status ON queue_entries(status)');
    await db.execute('CREATE INDEX idx_songs_title ON songs(title)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: add has_video column to songs
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE songs ADD COLUMN has_video INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// FOR TESTING ONLY — injects an already-open database, bypassing [init].
  // ignore: invalid_use_of_visible_for_testing_member
  void injectForTesting(Database database) {
    _db = database;
  }
}
