// lib/features/queue/presentation/add_song_screen.dart
// (Repurposed: no singer, just pick a song and add it to the queue)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/core/widgets/neon_card.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/library/data/song_model.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

class AddSongScreen extends ConsumerStatefulWidget {
  const AddSongScreen({super.key});

  @override
  ConsumerState<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends ConsumerState<AddSongScreen> {
  final _searchController = TextEditingController();
  Song? _selected;
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addToQueue() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a song first')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(queueNotifierProvider.notifier).addToQueue(_selected!.id!);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Song to Queue')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search songs…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) =>
                  ref.read(libraryProvider.notifier).search(q),
            ),
          ),
          Expanded(
            child: libraryAsync.when(
              data: (lib) {
                if (!lib.hasFolder) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off, size: 64, color: Colors.white24),
                        Gap(12),
                        Text('No folder selected yet.\nGo to Library first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  );
                }
                if (lib.songs.isEmpty) {
                  return const Center(
                    child: Text('No songs found',
                        style: TextStyle(color: Colors.white38)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lib.songs.length,
                  itemBuilder: (ctx, i) {
                    final song = lib.songs[i];
                    final isSelected = song.id == _selected?.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: NeonCard(
                        glowColor: isSelected ? AppTheme.primary : null,
                        onTap: () => setState(() => _selected = song),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.white24,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppTheme.primary : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (song.artist != null)
                                Text(song.artist!,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                              if (song.folderName != null)
                                Text(song.folderName!,
                                    style: const TextStyle(
                                        color: Colors.white30, fontSize: 11)),
                            ],
                          ),
                          trailing: Text(
                            song.displayDuration,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: (_loading || _selected == null) ? null : _addToQueue,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.add_to_queue),
            label: Text(_selected == null
                ? 'Select a song'
                : 'Add "${_selected!.title}" to Queue'),
          ),
        ),
      ),
    );
  }
}
