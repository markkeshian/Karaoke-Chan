// test/scanned_song_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaoke_chan/core/services/folder_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ScannedSong.fromFile', () {
    Directory? tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('karaoke_test_');
    });

    tearDown(() async {
      await tempDir?.delete(recursive: true);
    });

    File makeFile(String name) {
      final path = p.join(tempDir!.path, name);
      return File(path)..createSync();
    }

    test('parses "Artist - Title" pattern', () {
      final file = makeFile('Rick Astley - Never Gonna Give You Up.mp4');
      final song = ScannedSong.fromFile(file);

      expect(song.artist, 'Rick Astley');
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.filePath, file.path);
    });

    test('uses full filename as title when no dash separator', () {
      final file = makeFile('Bohemian Rhapsody.mp4');
      final song = ScannedSong.fromFile(file);

      expect(song.artist, isNull);
      expect(song.title, 'Bohemian Rhapsody');
    });

    test('uses first dash occurrence for artist/title split', () {
      final file = makeFile('AC-DC - Thunderstruck.mp4');
      final song = ScannedSong.fromFile(file);

      // "AC-DC" has no space/dash, but " - " is the separator
      expect(song.artist, 'AC-DC');
      expect(song.title, 'Thunderstruck');
    });

    test('trims whitespace from artist and title', () {
      final file = makeFile('  The Beatles  -  Hey Jude  .mp4');
      final song = ScannedSong.fromFile(file);

      expect(song.artist, 'The Beatles');
      expect(song.title, 'Hey Jude');
    });

    test('sets folderName to the parent directory name', () {
      final file = makeFile('test.mp4');
      final song = ScannedSong.fromFile(file);

      expect(song.folderName, p.basename(tempDir!.path));
    });

    test('handles nested directory correctly', () async {
      final subDir = await Directory(p.join(tempDir!.path, 'Pop')).create();
      final file = File(p.join(subDir.path, 'Queen - Bohemian Rhapsody.mp4'))
        ..createSync();
      final song = ScannedSong.fromFile(file);

      expect(song.folderName, 'Pop');
      expect(song.artist, 'Queen');
      expect(song.title, 'Bohemian Rhapsody');
    });
  });

  group('FolderScanner.scan', () {
    Directory? tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('karaoke_scan_');
    });

    tearDown(() async {
      await tempDir?.delete(recursive: true);
    });

    test('returns empty list for empty folder', () async {
      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);
      expect(songs, isEmpty);
    });

    test('finds supported video files', () async {
      File(p.join(tempDir!.path, 'Song A.mp4')).createSync();
      File(p.join(tempDir!.path, 'Song B.mkv')).createSync();
      File(p.join(tempDir!.path, 'not_media.txt')).createSync();

      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);

      expect(songs, hasLength(2));
      expect(songs.map((s) => s.title), containsAll(['Song A', 'Song B']));
    });

    test('finds supported audio files', () async {
      File(p.join(tempDir!.path, 'Song C.mp3')).createSync();
      File(p.join(tempDir!.path, 'Song D.flac')).createSync();

      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);

      expect(songs.map((s) => s.title), containsAll(['Song C', 'Song D']));
    });

    test('scans subdirectories recursively', () async {
      final sub = await Directory(p.join(tempDir!.path, 'sub')).create();
      File(p.join(tempDir!.path, 'Root Song.mp4')).createSync();
      File(p.join(sub.path, 'Sub Song.mp4')).createSync();

      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);

      expect(songs, hasLength(2));
      expect(songs.map((s) => s.title), containsAll(['Root Song', 'Sub Song']));
    });

    test('results are sorted alphabetically by title', () async {
      File(p.join(tempDir!.path, 'Zebra.mp4')).createSync();
      File(p.join(tempDir!.path, 'Apple.mp4')).createSync();
      File(p.join(tempDir!.path, 'Mango.mp4')).createSync();

      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);

      expect(songs.map((s) => s.title).toList(), ['Apple', 'Mango', 'Zebra']);
    });

    test('ignores unsupported file extensions', () async {
      File(p.join(tempDir!.path, 'doc.pdf')).createSync();
      File(p.join(tempDir!.path, 'image.png')).createSync();
      File(p.join(tempDir!.path, 'archive.zip')).createSync();
      File(p.join(tempDir!.path, 'valid.mp4')).createSync();

      final scanner = FolderScanner();
      final songs = await scanner.scan(tempDir!.path);

      expect(songs, hasLength(1));
      expect(songs.first.title, 'valid');
    });
  });
}
