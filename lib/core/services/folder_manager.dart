// lib/core/services/folder_manager.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderManager {
  static const _kFolderKey = 'karaoke_root_folder';

  /// Request storage read permissions on Android before picking a folder.
  /// Returns true if permission is granted (or if not on Android).
  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    // Android 13+ uses granular media permissions
    if (await Permission.videos.isGranted && await Permission.audio.isGranted) {
      return true;
    }

    // Request both video and audio for Android 13+
    final results = await [
      Permission.videos,
      Permission.audio,
    ].request();

    // Fallback: also try READ_EXTERNAL_STORAGE for Android ≤12
    if (results[Permission.videos] != PermissionStatus.granted) {
      final legacy = await Permission.storage.request();
      return legacy.isGranted;
    }

    return results[Permission.videos]!.isGranted;
  }

  Future<String?> getSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kFolderKey);
    if (path == null) return null;
    // Verify it still exists
    if (!Directory(path).existsSync()) {
      await clearFolder();
      return null;
    }
    return path;
  }

  Future<String?> pickFolder() async {
    // Request storage permission on Android before showing the picker
    final granted = await requestStoragePermission();
    if (!granted) return null;

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your Karaoke folder',
    );
    if (result == null) return null;
    await saveFolder(result);
    return result;
  }

  Future<void> saveFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFolderKey, path);
  }

  Future<void> clearFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFolderKey);
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

final folderManagerProvider = Provider<FolderManager>((_) => FolderManager());

/// The currently saved karaoke root folder path (null = not yet selected).
final savedFolderProvider = FutureProvider<String?>((ref) {
  return ref.watch(folderManagerProvider).getSavedFolder();
});
