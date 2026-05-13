// lib/core/services/folder_scanner.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// A song discovered during recursive folder scanning.
class ScannedSong {
  const ScannedSong({
    required this.title,
    required this.filePath,
    required this.folderName,
    this.artist,
  });

  final String title;
  final String filePath;
  final String folderName;
  final String? artist;

  /// Try to parse "Artist - Title" pattern from filename.
  factory ScannedSong.fromFile(File file) {
    final dir = p.dirname(file.path);
    final folderName = p.basename(dir);
    final raw = p.basenameWithoutExtension(file.path);

    final dashIdx = raw.indexOf(' - ');
    final String title;
    final String? artist;

    if (dashIdx != -1) {
      artist = raw.substring(0, dashIdx).trim();
      title = raw.substring(dashIdx + 3).trim();
    } else {
      artist = null;
      title = raw;
    }

    return ScannedSong(
      title: title,
      filePath: file.path,
      folderName: folderName,
      artist: artist,
    );
  }
}

class FolderScanner {
  static const _supportedExtensions = {
    // Video formats
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.flv', '.ts',
    // Audio-only formats
    '.mp3', '.flac', '.ogg', '.wav', '.m4a', '.aac', '.opus', '.wma', '.alac',
  };

  /// Scan [rootPath] recursively and return all karaoke files found.
  Future<List<ScannedSong>> scan(String rootPath) async {
    final songs = <ScannedSong>[];
    await _walk(Directory(rootPath), songs);
    songs.sort((a, b) => a.title.compareTo(b.title));
    return songs;
  }

  /// Same as [scan] but yields each file as it is discovered (true streaming).
  /// Suitable for driving a live progress indicator.
  Stream<ScannedSong> scanStream(String rootPath) {
    return _walkStream(Directory(rootPath));
  }

  Stream<ScannedSong> _walkStream(Directory dir) async* {
    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          yield* _walkStream(entity);
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_supportedExtensions.contains(ext)) {
            yield ScannedSong.fromFile(entity);
          }
        }
      }
    } catch (_) {
      // Skip unreadable directories (permission errors on Android, etc.)
    }
  }

  Future<void> _walk(Directory dir, List<ScannedSong> out) async {
    await for (final entity in dir.list(recursive: false)) {
      if (entity is Directory) {
        await _walk(entity, out);
      } else if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (_supportedExtensions.contains(ext)) {
          out.add(ScannedSong.fromFile(entity));
        }
      }
    }
  }
}

final folderScannerProvider = Provider<FolderScanner>((_) => FolderScanner());
