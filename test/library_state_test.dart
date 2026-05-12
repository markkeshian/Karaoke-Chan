// test/library_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';

void main() {
  group('LibraryState', () {
    const empty = LibraryState();

    test('default state values', () {
      expect(empty.folderPath, isNull);
      expect(empty.songs, isEmpty);
      expect(empty.status, ScanStatus.idle);
      expect(empty.scannedCount, 0);
      expect(empty.totalCount, 0);
      expect(empty.errorMessage, isNull);
      expect(empty.lastScanTime, isNull);
    });

    test('hasFolder is false with no folder', () {
      expect(empty.hasFolder, isFalse);
    });

    test('hasFolder is true when folderPath set', () {
      final s = empty.copyWith(folderPath: '/music');
      expect(s.hasFolder, isTrue);
    });

    test('isScanning is false by default', () {
      expect(empty.isScanning, isFalse);
    });

    test('isScanning is true during scanning', () {
      final s = empty.copyWith(status: ScanStatus.scanning);
      expect(s.isScanning, isTrue);
    });

    test('copyWith updates individual fields', () {
      final songs = [
        Song(id: 1, title: 'Song A', filePath: '/a.cdg'),
        Song(id: 2, title: 'Song B', filePath: '/b.cdg'),
      ];
      final s = empty.copyWith(
        folderPath: '/music',
        songs: songs,
        status: ScanStatus.done,
        scannedCount: 2,
        totalCount: 2,
        lastScanTime: DateTime(2026, 1, 1),
      );

      expect(s.folderPath, '/music');
      expect(s.songs, hasLength(2));
      expect(s.status, ScanStatus.done);
      expect(s.scannedCount, 2);
      expect(s.totalCount, 2);
      expect(s.lastScanTime, DateTime(2026, 1, 1));
    });

    test('copyWith clearFolder removes folderPath', () {
      final s = empty.copyWith(folderPath: '/music');
      final cleared = s.copyWith(clearFolder: true);
      expect(cleared.folderPath, isNull);
      expect(cleared.hasFolder, isFalse);
    });

    test('copyWith preserves folderPath when not clearing', () {
      final s = empty.copyWith(folderPath: '/music');
      final updated = s.copyWith(status: ScanStatus.scanning);
      expect(updated.folderPath, '/music');
    });

    test('copyWith sets error status and message', () {
      final s = empty.copyWith(
        status: ScanStatus.error,
        errorMessage: 'Permission denied',
      );
      expect(s.status, ScanStatus.error);
      expect(s.errorMessage, 'Permission denied');
    });

    test('songs list is independent per instance', () {
      final songs = [Song(id: 1, title: 'A', filePath: '/a.cdg')];
      final s1 = empty.copyWith(songs: songs);
      final s2 = empty.copyWith(songs: []);

      expect(s1.songs, hasLength(1));
      expect(s2.songs, isEmpty);
    });
  });
}

