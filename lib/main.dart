// lib/main.dart
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape on Android and enter persistent immersive mode so the
  // system bars are always hidden (karaoke display — no need for status/nav bar).
  if (!kIsWeb && Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

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

class _KaraokeAppState extends ConsumerState<KaraokeApp>
    with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can reset immersive mode when the app is backgrounded/resumed.
    // Re-apply it each time we come back to the foreground.
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
