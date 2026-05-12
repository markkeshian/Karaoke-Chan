// lib/core/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:karaoke_chan/features/home/presentation/home_screen.dart';
import 'package:karaoke_chan/features/queue/presentation/queue_screen.dart';
import 'package:karaoke_chan/features/player/presentation/player_screen.dart';
import 'package:karaoke_chan/features/player/presentation/karaoke_overlay.dart';
import 'package:karaoke_chan/features/library/presentation/library_screen.dart';
import 'package:karaoke_chan/features/settings/presentation/settings_screen.dart';
import 'package:karaoke_chan/features/queue/presentation/add_song_screen.dart';
import 'package:karaoke_chan/core/widgets/scaffold_with_nav.dart';

// Route names
class AppRoutes {
  static const home = '/';
  static const queue = '/queue';
  static const player = '/player';
  static const overlay = '/overlay';
  static const library = '/library';
  static const settings = '/settings';
  static const addSong = '/add-song';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNav(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.queue,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: QueueScreen()),
          ),
          GoRoute(
            path: AppRoutes.library,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LibraryScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: AppRoutes.overlay,
        builder: (context, state) => const KaraokeOverlay(),
      ),
      GoRoute(
        path: AppRoutes.addSong,
        builder: (context, state) => const AddSongScreen(),
      ),
    ],
  );
});

