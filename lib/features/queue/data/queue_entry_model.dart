// lib/features/queue/data/queue_entry_model.dart
import 'package:karaoke_chan/features/library/data/song_model.dart';

enum QueueStatus { waiting, playing, done, skipped }

class QueueEntry {
  QueueEntry({
    this.id,
    required this.songId,
    required this.position,
    this.status = QueueStatus.waiting,
    DateTime? addedAt,
    this.startedAt,
    this.finishedAt,
    this.song,
  }) : addedAt = addedAt ?? DateTime.now();

  final int? id;
  final int songId;
  final int position;
  final QueueStatus status;
  final DateTime addedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  // Joined (populated by repository)
  final Song? song;

  QueueEntry copyWith({
    int? id,
    int? songId,
    int? position,
    QueueStatus? status,
    DateTime? addedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    Song? song,
  }) {
    return QueueEntry(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      position: position ?? this.position,
      status: status ?? this.status,
      addedAt: addedAt ?? this.addedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      song: song ?? this.song,
    );
  }

  factory QueueEntry.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    DateTime? parseDate(Object? v) {
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    return QueueEntry(
      id: asInt(map['id']),
      songId: asInt(map['song_id']) ?? 0,
      position: asInt(map['position']) ?? 0,
      status: QueueStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => QueueStatus.waiting,
      ),
      addedAt: parseDate(map['added_at']) ?? DateTime.now(),
      startedAt: parseDate(map['started_at']),
      finishedAt: parseDate(map['finished_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'song_id': songId,
      'position': position,
      'status': status.name,
      'added_at': addedAt.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'finished_at': finishedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) => other is QueueEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
