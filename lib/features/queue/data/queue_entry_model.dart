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
    return QueueEntry(
      id: map['id'] as int?,
      songId: map['song_id'] as int,
      position: map['position'] as int,
      status: QueueStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => QueueStatus.waiting,
      ),
      addedAt: DateTime.parse(map['added_at'] as String),
      startedAt: map['started_at'] != null
          ? DateTime.parse(map['started_at'] as String)
          : null,
      finishedAt: map['finished_at'] != null
          ? DateTime.parse(map['finished_at'] as String)
          : null,
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
