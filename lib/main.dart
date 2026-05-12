// lib/main.dart
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit
  MediaKit.ensureInitialized();

  // Initialize database
  await DatabaseHelper.instance.init();

  runApp(
    const ProviderScope(
      child: KaraokeApp(),
    ),
  );
}

class KaraokeApp extends ConsumerStatefulWidget {
  const KaraokeApp({super.key});

  @override
  ConsumerState<KaraokeApp> createState() => _KaraokeAppState();
}

class _KaraokeAppState extends ConsumerState<KaraokeApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      // Fires on macOS/Windows when the last window is closed.
      onExitRequested: () async {
        await _clearSessionData();
        return AppExitResponse.exit;
      },
      // Fires when the app is being detached (process ending).
      onDetach: () => _clearSessionData(),
    );
  }

  Future<void> _clearSessionData() async {
    try {
      // Clear queue directly via repository so it works even if the
      // notifier has already been disposed.
      await ref.read(queueRepositoryProvider).clearAll();
    } catch (_) {
      // Best-effort — ignore errors during shutdown.
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Karaoke Chan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
