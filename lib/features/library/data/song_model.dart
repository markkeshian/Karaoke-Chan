// lib/features/library/data/song_model.dart

class Song {
  Song({
    this.id,
    required this.title,
    this.artist,
    required this.filePath,
    this.folderName,
    this.durationMs,
    this.coverArtPath,
    this.playCount = 0,
    this.lastPlayedAt,
    this.hasVideo = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final int? id;
  final String title;
  final String? artist;
  final String filePath;
  final String? folderName;
  final int? durationMs;
  final String? coverArtPath;
  final int playCount;
  final DateTime? lastPlayedAt;

  /// Whether this song file contains a video track (stored in DB).
  final bool hasVideo;
  final DateTime addedAt;

  Song copyWith({
    int? id,
    String? title,
    String? artist,
    String? filePath,
    String? folderName,
    int? durationMs,
    String? coverArtPath,
    int? playCount,
    DateTime? lastPlayedAt,
    bool? hasVideo,
    DateTime? addedAt,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      filePath: filePath ?? this.filePath,
      folderName: folderName ?? this.folderName,
      durationMs: durationMs ?? this.durationMs,
      coverArtPath: coverArtPath ?? this.coverArtPath,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      hasVideo: hasVideo ?? this.hasVideo,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    // Defensive casts: some sqflite backends return numerics as `num`/`BigInt`
    // rather than `int`, which would throw on a direct `as int?` cast.
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    DateTime? parseDate(Object? v) {
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    return Song(
      id: asInt(map['id']),
      title: (map['title'] as String?) ?? '',
      artist: map['artist'] as String?,
      filePath: (map['file_path'] as String?) ?? '',
      folderName: map['folder_name'] as String?,
      durationMs: asInt(map['duration_ms']),
      coverArtPath: map['cover_art_path'] as String?,
      playCount: asInt(map['play_count']) ?? 0,
      lastPlayedAt: parseDate(map['last_played_at']),
      hasVideo: (asInt(map['has_video']) ?? 0) != 0,
      addedAt: parseDate(map['added_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'artist': artist,
      'file_path': filePath,
      'folder_name': folderName,
      'duration_ms': durationMs,
      'cover_art_path': coverArtPath,
      'play_count': playCount,
      'has_video': hasVideo ? 1 : 0,
      'last_played_at': lastPlayedAt?.toIso8601String(),
      'added_at': addedAt.toIso8601String(),
    };
  }

  String get displayDuration {
    if (durationMs == null) return '--:--';
    final total = Duration(milliseconds: durationMs!);
    final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
