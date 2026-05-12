// lib/core/services/file_watcher.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Watches a folder tree for new or deleted karaoke files and emits
/// [FolderChangeEvent]s so the library can update without manual refresh.
class FileWatcherService {
  FileWatcherService();

  StreamSubscription<FileSystemEvent>? _sub;
  final _controller = StreamController<FolderChangeEvent>.broadcast();

  Stream<FolderChangeEvent> get changes => _controller.stream;

  void watch(String rootPath) {
    _sub?.cancel();
    try {
      _sub = Directory(rootPath)
          .watch(recursive: true)
          .where((e) => _isKaraokeFile(e.path))
          .listen((event) {
        if (event.type == FileSystemEvent.create) {
          _controller.add(FolderChangeEvent.added(event.path));
        } else if (event.type == FileSystemEvent.delete) {
          _controller.add(FolderChangeEvent.removed(event.path));
        }
      });
    } catch (_) {
      // Directory watching not supported on all platforms/permissions
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  static bool _isKaraokeFile(String path) {
    final ext = p.extension(path).toLowerCase();
    const supported = {
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.webm',
      '.m4v',
      '.mp3',
      '.flac',
      '.ogg',
      '.wav',
      '.m4a',
      '.aac',
    };
    return supported.contains(ext);
  }
}

class FolderChangeEvent {
  const FolderChangeEvent.added(this.path) : type = FolderChangeType.added;
  const FolderChangeEvent.removed(this.path) : type = FolderChangeType.removed;

  final String path;
  final FolderChangeType type;
}

enum FolderChangeType { added, removed }

final fileWatcherProvider = Provider<FileWatcherService>((ref) {
  final watcher = FileWatcherService();
  ref.onDispose(watcher.dispose);
  return watcher;
});
