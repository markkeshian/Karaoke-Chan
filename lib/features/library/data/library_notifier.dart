// lib/features/library/data/library_notifier.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:karaoke_chan/core/services/file_watcher.dart';
import 'package:karaoke_chan/core/services/folder_manager.dart';
import 'package:karaoke_chan/core/services/folder_scanner.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';

enum ScanStatus { idle, scanning, done, error }

class LibraryState {
  const LibraryState({
    this.folderPath,
    this.songs = const [],
    this.status = ScanStatus.idle,
    this.scannedCount = 0,
    this.totalCount = 0,
    this.errorMessage,
    this.lastScanTime,
  });

  final String? folderPath;
  final List<Song> songs;
  final ScanStatus status;
  final int scannedCount;
  final int totalCount;
  final String? errorMessage;
  final DateTime? lastScanTime;

  bool get hasFolder => folderPath != null;
  bool get isScanning => status == ScanStatus.scanning;

  LibraryState copyWith({
    String? folderPath,
    List<Song>? songs,
    ScanStatus? status,
    int? scannedCount,
    int? totalCount,
    String? errorMessage,
    DateTime? lastScanTime,
    bool clearFolder = false,
  }) {
    return LibraryState(
      folderPath: clearFolder ? null : (folderPath ?? this.folderPath),
      songs: songs ?? this.songs,
      status: status ?? this.status,
      scannedCount: scannedCount ?? this.scannedCount,
      totalCount: totalCount ?? this.totalCount,
      errorMessage: errorMessage ?? this.errorMessage,
      lastScanTime: lastScanTime ?? this.lastScanTime,
    );
  }
}

class LibraryNotifier extends AsyncNotifier<LibraryState> {
  StreamSubscription? _watcherSub;

  @override
  Future<LibraryState> build() async {
    ref.onDispose(() => _watcherSub?.cancel());

    final folder = await ref.watch(folderManagerProvider).getSavedFolder();
    if (folder == null) return const LibraryState();

    // Load songs already in DB
    final songs = await ref.read(songRepositoryProvider).getAll();

    // Start file watcher
    _startWatcher(folder);

    return LibraryState(folderPath: folder, songs: songs, status: ScanStatus.done);
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  Future<void> pickFolder() async {
    final manager = ref.read(folderManagerProvider);
    final path = await manager.pickFolder();
    if (path == null) return;

    _update((s) => s.copyWith(folderPath: path, songs: const [], status: ScanStatus.idle));
    await scanFolder();
  }

  Future<void> scanFolder() async {
    final folderPath = state.value?.folderPath;
    if (folderPath == null) return;

    _update((s) => s.copyWith(status: ScanStatus.scanning, scannedCount: 0));

    try {
      final scanner = ref.read(folderScannerProvider);
      final scanned = await scanner.scan(folderPath);

      final songRepo = ref.read(songRepositoryProvider);

      // Bulk-upsert: delete songs from this folder path root, re-insert
      await songRepo.deleteByFolderRoot(folderPath);
      final inserted = <Song>[];
      for (int i = 0; i < scanned.length; i++) {
        final s = scanned[i];
        final song = await songRepo.insert(Song(
          title: s.title,
          artist: s.artist,
          filePath: s.filePath,
          folderName: s.folderName,
        ));
        inserted.add(song);
        _update((st) => st.copyWith(scannedCount: i + 1, totalCount: scanned.length));
      }

      _startWatcher(folderPath);

      _update((s) => s.copyWith(
            songs: inserted,
            status: ScanStatus.done,
            lastScanTime: DateTime.now(),
          ));
    } catch (e) {
      _update((s) => s.copyWith(
            status: ScanStatus.error,
            errorMessage: e.toString(),
          ));
    }
  }

  Future<void> changeFolder() async {
    final manager = ref.read(folderManagerProvider);
    await manager.clearFolder();
    _watcherSub?.cancel();
    _update((s) => LibraryState());
    await pickFolder();
  }

  Future<void> search(String query) async {
    final folderPath = state.value?.folderPath;
    final songs = await ref
        .read(songRepositoryProvider)
        .getAll(search: query.isEmpty ? null : query);
    _update((s) => s.copyWith(songs: songs));
  }

  // ─── Watcher ───────────────────────────────────────────────────────────────

  void _startWatcher(String path) {
    _watcherSub?.cancel();
    final watcher = ref.read(fileWatcherProvider);
    watcher.watch(path);
    _watcherSub = watcher.changes.listen((event) async {
      if (event.type == FolderChangeType.added) {
        await _onFileAdded(event.path);
      } else {
        await _onFileRemoved(event.path);
      }
    });
  }

  Future<void> _onFileAdded(String filePath) async {
    final songRepo = ref.read(songRepositoryProvider);
    final scanned = ScannedSong.fromFile(File(filePath));
    final song = await songRepo.insert(Song(
      title: scanned.title,
      artist: scanned.artist,
      filePath: scanned.filePath,
      folderName: scanned.folderName,
    ));
    _update((s) => s.copyWith(songs: [...s.songs, song]
      ..sort((a, b) => a.title.compareTo(b.title))));
  }

  Future<void> _onFileRemoved(String filePath) async {
    final songRepo = ref.read(songRepositoryProvider);
    await songRepo.deleteByPath(filePath);
    _update((s) => s.copyWith(
        songs: s.songs.where((song) => song.filePath != filePath).toList()));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  void _update(LibraryState Function(LibraryState) updater) {
    if (state.hasValue) state = AsyncData(updater(state.value!));
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
