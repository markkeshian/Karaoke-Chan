// lib/features/queue/data/queue_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karaoke_chan/features/queue/data/queue_entry_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';

class QueueNotifier extends AsyncNotifier<List<QueueEntry>> {
  @override
  Future<List<QueueEntry>> build() {
    return ref.watch(queueRepositoryProvider).getActive();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(queueRepositoryProvider).getActive(),
    );
  }

  Future<void> enqueue(int songId) async {
    await ref.read(queueRepositoryProvider).enqueue(songId);
    await refresh();
  }

  Future<void> remove(int entryId) async {
    await ref.read(queueRepositoryProvider).remove(entryId);
    await refresh();
  }

  Future<void> reorder(List<QueueEntry> entries) async {
    // Apply optimistic update immediately so the UI feels instant.
    final previous = state;
    state = AsyncData(entries);
    try {
      final ids = entries.map((e) => e.id!).toList();
      await ref.read(queueRepositoryProvider).reorder(ids);
    } catch (_) {
      // Persist failed — roll back to previous state.
      state = previous;
      rethrow;
    }
  }

  Future<void> clearAll() async {
    await ref.read(queueRepositoryProvider).clearAll();
    await refresh();
  }
}

final queueNotifierProvider =
    AsyncNotifierProvider<QueueNotifier, List<QueueEntry>>(QueueNotifier.new);
