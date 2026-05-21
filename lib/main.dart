// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';

/// Write [message] to a crash log in the app support directory on Windows so
/// that even a completely silent crash leaves a breadcrumb for debugging.
Future<void> _writeCrashLog(String message) async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File(p.join(dir.path, 'crash_log.txt'));
    final timestamp = DateTime.now().toIso8601String();
    await logFile.writeAsString(
      '$timestamp\n$message\n---\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // Best-effort — never let the log writer itself crash the app.
  }
}

Future<void> main() async {
  // Install the zone-based error handler FIRST so any error that escapes
  // during startup is caught, logged, and shown to the user rather than
  // killing the process silently (which is what produces the "no crash log"
  // symptom on Windows / Microsoft Store certification machines).
  await runZonedGuarded(
    _bootstrap,
    (error, stack) async {
      await _writeCrashLog('Unhandled zone error:\n$error\n$stack');
      // If Flutter is already running, show an overlay error; otherwise
      // just rethrow so the process exits with a message in the console.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route all Flutter framework errors to the same log.
  FlutterError.onError = (details) async {
    FlutterError.presentError(details);
    await _writeCrashLog(
      'Flutter framework error:\n${details.exception}\n${details.stack}',
    );
  };

  // Catch uncaught async errors that bypass the zone (e.g. from platform
  // isolates). This is the last-resort handler before the OS kills the process.
  PlatformDispatcher.instance.onError = (error, stack) {
    _writeCrashLog('PlatformDispatcher error:\n$error\n$stack');
    return true; // Marks the error as handled so Flutter doesn't also crash.
  };

  // Force landscape on Android and enter persistent immersive mode so the
  // system bars are always hidden (karaoke display — no need for status/nav bar).
  if (!kIsWeb && Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // Initialize media_kit — must come before any Player is created.
  MediaKit.ensureInitialized();

  // Initialize database — on desktop this loads sqlite3.dll via FFI.
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
