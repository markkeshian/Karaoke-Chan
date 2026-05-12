// test/library_screen_test.dart
//
// Widget tests for LibraryScreen and its private sub-widgets.
// Uses ProviderScope overrides to inject controlled state without
// touching the real database or file-system.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'package:karaoke_chan/features/library/presentation/library_screen.dart';

// ─── Fake notifiers ───────────────────────────────────────────────────────────

/// A fake LibraryNotifier that returns an arbitrary [LibraryState] immediately.
class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(this._state);
  final LibraryState _state;

  @override
  Future<LibraryState> build() async => _state;

  // No-op overrides so tests never touch IO.
  @override
  Future<void> pickFolder() async {}
  @override
  Future<void> scanFolder() async {}
  @override
  Future<void> changeFolder() async {}
  @override
  Future<void> search(String query) async {}
}

/// A fake SongRepository that records calls and returns empty results.
class _FakeSongRepository implements SongRepository {
  final List<int> deletedIds = [];

  @override
  Future<List<Song>> getAll({String? search}) async => [];

  @override
  Future<Song?> getById(int id) async => null;

  @override
  Future<Song> insert(Song song) async => song.copyWith(id: 999);

  @override
  Future<List<Song>> insertAll(List<Song> songs) async =>
      songs.map((s) => s.copyWith(id: 999)).toList();

  @override
  Future<void> update(Song song) async {}

  @override
  Future<void> delete(int id) async => deletedIds.add(id);

  @override
  Future<void> deleteByPath(String filePath) async {}

  @override
  Future<void> deleteByFolderRoot(String rootPath) async {}

  @override
  Future<void> incrementPlayCount(int songId) async {}

  @override
  Future<List<Song>> getTopPlayed({int limit = 10}) async => [];

  @override
  Future<Map<String, List<Song>>> getDuplicates() async => {};
}

// ─── Helper ───────────────────────────────────────────────────────────────────

/// Wraps [LibraryScreen] in a minimal app with the given provider overrides.
Widget _buildApp({
  required LibraryState libraryState,
  Map<String, List<Song>> duplicates = const {},
  SongRepository? songRepo,
}) {
  final fakeSongRepo = songRepo ?? _FakeSongRepository();

  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(() => _FakeLibraryNotifier(libraryState)),
      duplicatesProvider.overrideWith((_) async => duplicates),
      songRepositoryProvider.overrideWithValue(fakeSongRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: const LibraryScreen(),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('LibraryScreen – loading state', () {
    testWidgets('shows CircularProgressIndicator while provider is loading',
        (tester) async {
      // We can't easily produce an async-loading provider through the notifier,
      // so we test it via an overrideWith that never resolves... instead we
      // verify the other states more deeply and just check the build output.
      //
      // Provide a loading AsyncValue by using a notifier that delays.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Return a future that does not resolve during the test frame.
            libraryProvider.overrideWith(() => _SlowLibraryNotifier()),
            duplicatesProvider
                .overrideWith((_) async => <String, List<Song>>{}),
            songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const LibraryScreen(),
          ),
        ),
      );
      // First frame: provider is loading.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('LibraryScreen – no folder selected', () {
    testWidgets('shows "Select Karaoke Folder" heading', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      expect(find.text('Select Karaoke Folder'), findsOneWidget);
    });

    testWidgets('shows "Choose Folder" button', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      expect(find.text('Choose Folder'), findsOneWidget);
    });

    testWidgets('shows folder_special icon', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_special), findsOneWidget);
    });

    testWidgets('shows supported formats hint text', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('MP4'),
        findsWidgets,
      );
    });

    testWidgets('renders example folder structure tree', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      // The _Tree widget renders these strings.
      expect(find.textContaining('Karaoke/'), findsOneWidget);
      expect(find.textContaining('English/'), findsOneWidget);
      expect(find.textContaining('My Way.mp4'), findsOneWidget);
    });

    testWidgets('shows "Example structure" card label', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: const LibraryState()));
      await tester.pumpAndSettle();

      expect(find.text('Example structure'), findsOneWidget);
    });
  });

  group('LibraryScreen – scanning state', () {
    testWidgets('shows "Scanning Folder…" text', (tester) async {
      const state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.scanning,
        scannedCount: 5,
        totalCount: 20,
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('Scanning Folder…'), findsOneWidget);
    });

    testWidgets('shows scannedCount in progress text', (tester) async {
      const state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.scanning,
        scannedCount: 7,
        totalCount: 20,
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('7 songs found'), findsOneWidget);
    });

    testWidgets('shows folder path below progress bar', (tester) async {
      const state = LibraryState(
        folderPath: '/Users/chan/music',
        status: ScanStatus.scanning,
        scannedCount: 0,
        totalCount: 0,
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('/Users/chan/music'), findsOneWidget);
    });

    testWidgets('shows LinearProgressIndicator', (tester) async {
      const state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.scanning,
        scannedCount: 10,
        totalCount: 50,
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('LibraryScreen – song list', () {
    final songs = [
      Song(
          id: 1,
          title: 'My Way',
          artist: 'Frank',
          filePath: '/a.mp4',
          folderName: 'English',
          hasVideo: true),
      Song(
          id: 2,
          title: 'Hello',
          artist: 'Adele',
          filePath: '/b.mp4',
          folderName: 'English',
          hasVideo: true),
    ];

    LibraryState songState({List<Song>? overrideSongs}) => LibraryState(
          folderPath: '/music',
          status: ScanStatus.done,
          songs: overrideSongs ?? songs,
          lastScanTime: DateTime(2026, 5, 12, 10, 0),
        );

    testWidgets('renders one tile per song', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.text('My Way'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows artist names in subtitles', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.text('Frank'), findsOneWidget);
      expect(find.text('Adele'), findsOneWidget);
    });

    testWidgets('shows folder name in subtitle', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      // Both songs are in "English"; two tiles display it.
      expect(find.text('English'), findsWidgets);
    });

    testWidgets('stats bar shows correct song count', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.text('2 songs'), findsOneWidget);
    });

    testWidgets('stats bar shows folder path', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.text('/music'), findsOneWidget);
    });

    testWidgets('shows search TextField', (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows empty-search widget when songs list is empty',
        (tester) async {
      await tester
          .pumpWidget(_buildApp(libraryState: songState(overrideSongs: [])));
      await tester.pumpAndSettle();

      expect(find.text('No songs match your search'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('shows refresh and change-folder icons in AppBar',
        (tester) async {
      await tester.pumpWidget(_buildApp(libraryState: songState()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });
  });

  group('LibraryScreen – duplicates banner', () {
    final stateWithSongs = LibraryState(
      folderPath: '/music',
      status: ScanStatus.done,
      songs: [
        Song(id: 1, title: 'My Way', filePath: '/a/My Way.mp4'),
        Song(id: 2, title: 'My Way', filePath: '/b/My Way.mp4'),
      ],
    );

    testWidgets('banner is hidden when no duplicates', (tester) async {
      await tester.pumpWidget(
        _buildApp(libraryState: stateWithSongs, duplicates: {}),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.content_copy), findsNothing);
      expect(find.textContaining('duplicate group'), findsNothing);
    });

    testWidgets('banner shows duplicate count when duplicates exist',
        (tester) async {
      final dups = {
        'My Way': [
          Song(id: 1, title: 'My Way', filePath: '/a/My Way.mp4'),
          Song(id: 2, title: 'My Way', filePath: '/b/My Way.mp4'),
        ],
      };
      await tester.pumpWidget(
        _buildApp(libraryState: stateWithSongs, duplicates: dups),
      );
      await tester.pumpAndSettle();

      // Banner text: "2 songs in 1 duplicate group — tap to review"
      expect(find.textContaining('duplicate group'), findsOneWidget);
      expect(find.textContaining('2 songs'), findsOneWidget);
    });

    testWidgets('banner uses plural "groups" when more than one group',
        (tester) async {
      final dups = {
        'My Way': [
          Song(id: 1, title: 'My Way', filePath: '/a/My Way.mp4'),
          Song(id: 2, title: 'My Way', filePath: '/b/My Way.mp4'),
        ],
        'Hello': [
          Song(id: 3, title: 'Hello', filePath: '/a/Hello.mp4'),
          Song(id: 4, title: 'Hello', filePath: '/b/Hello.mp4'),
        ],
      };
      await tester.pumpWidget(
        _buildApp(libraryState: stateWithSongs, duplicates: dups),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('duplicate groups'), findsOneWidget);
    });
  });

  group('LibraryScreen – error state', () {
    testWidgets('shows error message text', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWith(() => _ErrorLibraryNotifier()),
            duplicatesProvider
                .overrideWith((_) async => <String, List<Song>>{}),
            songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });

  group('_StatsBar timeAgo logic (via widget)', () {
    testWidgets('shows "just now" for very recent scan', (tester) async {
      final state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.done,
        songs: const [],
        lastScanTime: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('Scanned just now'), findsOneWidget);
    });

    testWidgets('shows minutes-ago for scan within the last hour',
        (tester) async {
      final state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.done,
        songs: const [],
        lastScanTime: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('Scanned 15m ago'), findsOneWidget);
    });

    testWidgets('shows hours-ago for scan within the last day', (tester) async {
      final state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.done,
        songs: const [],
        lastScanTime: DateTime.now().subtract(const Duration(hours: 3)),
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('Scanned 3h ago'), findsOneWidget);
    });

    testWidgets('shows days-ago for scan older than a day', (tester) async {
      final state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.done,
        songs: const [],
        lastScanTime: DateTime.now().subtract(const Duration(days: 2)),
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.text('Scanned 2d ago'), findsOneWidget);
    });

    testWidgets('shows nothing when lastScanTime is null', (tester) async {
      const state = LibraryState(
        folderPath: '/music',
        status: ScanStatus.done,
      );
      await tester.pumpWidget(_buildApp(libraryState: state));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scanned'), findsNothing);
    });
  });
}

// ─── Extra fake notifiers used above ─────────────────────────────────────────

/// A notifier that never resolves (stays in loading state).
class _SlowLibraryNotifier extends LibraryNotifier {
  @override
  Future<LibraryState> build() => Completer<LibraryState>().future;
}

/// A notifier that immediately throws.
class _ErrorLibraryNotifier extends LibraryNotifier {
  @override
  Future<LibraryState> build() async => throw Exception('scan failed');
}
