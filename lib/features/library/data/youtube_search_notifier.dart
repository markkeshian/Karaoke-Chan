// lib/features/library/data/youtube_search_notifier.dart
//
// Riverpod state for YouTube search results.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karaoke_chan/core/services/youtube_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum YoutubeSearchStatus { idle, loading, done, error }

class YoutubeSearchState {
  const YoutubeSearchState({
    this.query = '',
    this.results = const [],
    this.status = YoutubeSearchStatus.idle,
    this.errorMessage,
  });

  final String query;
  final List<YoutubeVideoResult> results;
  final YoutubeSearchStatus status;
  final String? errorMessage;

  bool get isIdle => status == YoutubeSearchStatus.idle;
  bool get isLoading => status == YoutubeSearchStatus.loading;
  bool get hasResults =>
      status == YoutubeSearchStatus.done && results.isNotEmpty;
  bool get isEmpty => status == YoutubeSearchStatus.done && results.isEmpty;

  YoutubeSearchState copyWith({
    String? query,
    List<YoutubeVideoResult>? results,
    YoutubeSearchStatus? status,
    String? errorMessage,
  }) =>
      YoutubeSearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class YoutubeSearchNotifier extends Notifier<YoutubeSearchState> {
  @override
  YoutubeSearchState build() => const YoutubeSearchState();

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const YoutubeSearchState();
      return;
    }

    state = state.copyWith(
      query: query,
      status: YoutubeSearchStatus.loading,
      results: [],
      errorMessage: null,
    );

    try {
      final results =
          await ref.read(youtubeServiceProvider).searchVideos(query);
      state = state.copyWith(
        results: results,
        status: YoutubeSearchStatus.done,
      );
    } catch (e) {
      state = state.copyWith(
        status: YoutubeSearchStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void clear() => state = const YoutubeSearchState();
}

// ── Provider ──────────────────────────────────────────────────────────────────

final youtubeSearchProvider =
    NotifierProvider<YoutubeSearchNotifier, YoutubeSearchState>(
        YoutubeSearchNotifier.new);
