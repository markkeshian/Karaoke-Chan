// lib/core/services/youtube_service.dart
//
// Search  → YouTube Innertube API (no scraping, no API key, no bot blocks)
// Streams → youtube_explode_dart (resolves direct playable URLs)

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class YoutubeVideoResult {
  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;
  final String thumbnailUrl;

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';
}

// ── Service ───────────────────────────────────────────────────────────────────

class YoutubeService {
  // Keep youtube_explode_dart only for stream URL resolution.
  final _yt = YoutubeExplode();

  // ── Innertube constants ────────────────────────────────────────────────────
  static const _innertubeKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _clientName = 'WEB';
  static const _clientVersion = '2.20240101.00.00';
  static const _searchParams = 'EgIQAQ=='; // filter: videos only

  /// Search via the Innertube API — no web scraping, no bot blocks.
  Future<List<YoutubeVideoResult>> searchVideos(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(
      'https://www.youtube.com/youtubei/v1/search'
      '?key=$_innertubeKey&prettyPrint=false',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'X-Youtube-Client-Name': '1',
        'X-Youtube-Client-Version': _clientVersion,
      },
      body: jsonEncode({
        'context': {
          'client': {
            'clientName': _clientName,
            'clientVersion': _clientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': query,
        'params': _searchParams,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('YouTube search failed (HTTP ${response.statusCode})');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseResults(json);
  }

  List<YoutubeVideoResult> _parseResults(Map<String, dynamic> json) {
    final results = <YoutubeVideoResult>[];
    try {
      final sections = json['contents']['twoColumnSearchResultsRenderer']
              ['primaryContents']['sectionListRenderer']['contents']
          as List<dynamic>;

      for (final section in sections) {
        final items =
            section['itemSectionRenderer']?['contents'] as List<dynamic>?;
        if (items == null) continue;

        for (final item in items) {
          final video = item['videoRenderer'] as Map<String, dynamic>?;
          if (video == null) continue;

          final videoId = video['videoId'] as String?;
          if (videoId == null) continue;

          final title = (video['title']?['runs'] as List<dynamic>?)
                  ?.firstOrNull?['text'] as String? ??
              'Unknown';

          final channel = (video['ownerText']?['runs'] as List<dynamic>?)
                  ?.firstOrNull?['text'] as String? ??
              '';

          final durationText = video['lengthText']?['simpleText'] as String?;
          final duration =
              durationText != null ? _parseDuration(durationText) : null;

          final thumbList = video['thumbnail']?['thumbnails'] as List<dynamic>?;
          final thumbnailUrl = (thumbList != null && thumbList.isNotEmpty)
              ? (thumbList.last['url'] as String? ??
                  'https://i.ytimg.com/vi/$videoId/mqdefault.jpg')
              : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

          results.add(YoutubeVideoResult(
            videoId: videoId,
            title: title,
            channel: channel,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
          ));
        }
      }
    } catch (_) {
      // Return whatever was parsed before the error.
    }
    return results;
  }

  Duration _parseDuration(String text) {
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.length == 3) {
      return Duration(
          hours: parts[0] ?? 0, minutes: parts[1] ?? 0, seconds: parts[2] ?? 0);
    } else if (parts.length == 2) {
      return Duration(minutes: parts[0] ?? 0, seconds: parts[1] ?? 0);
    }
    return Duration.zero;
  }

  /// Resolves the best available stream URL for a YouTube video.
  Future<String?> getBestStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      // Prefer muxed (video+audio) — best for karaoke.
      for (final stream in manifest.muxed.sortByVideoQuality()) {
        try {
          final url = stream.url.toString();
          if (url.isNotEmpty) return url;
        } catch (_) {
          continue;
        }
      }

      // Fallback: audio-only.
      for (final stream in manifest.audioOnly.sortByBitrate().reversed) {
        try {
          final url = stream.url.toString();
          if (url.isNotEmpty) return url;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    return null;
  }

  void dispose() => _yt.close();
}

// ── Provider ──────────────────────────────────────────────────────────────────

final youtubeServiceProvider = Provider<YoutubeService>((ref) {
  final svc = YoutubeService();
  ref.onDispose(svc.dispose);
  return svc;
});
