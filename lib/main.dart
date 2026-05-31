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

  // Web is not a supported platform: the library scanner relies on dart:io
  // file APIs, and sqflite has no web implementation. Show a clear message
  // instead of letting initialization crash.
  if (kIsWeb) {
    runApp(const _UnsupportedPlatformApp());
    return;
  }

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
  // Wrap in try/catch: if the native libs failed to load for any reason
  // (corrupt MSIX, missing VC++ runtime, etc.) we still want to show an
  // error UI instead of crashing the process silently.
  Object? mediaKitError;
  try {
    MediaKit.ensureInitialized();
  } catch (e, st) {
    mediaKitError = e;
    await _writeCrashLog('MediaKit.ensureInitialized failed:\n$e\n$st');
  }

  // Initialize database — on desktop this loads sqlite3.dll via FFI.
  Object? dbError;
  try {
    await DatabaseHelper.instance.init();
  } catch (e, st) {
    dbError = e;
    await _writeCrashLog('DatabaseHelper.init failed:\n$e\n$st');
  }

  if (mediaKitError != null || dbError != null) {
    runApp(_StartupErrorApp(
      mediaKitError: mediaKitError,
      dbError: dbError,
    ));
    return;
  }

  runApp(
    const ProviderScope(
      child: KaraokeApp(),
    ),
  );
}

/// Minimal fallback UI shown when a critical startup step fails. Keeps the
/// process alive (so Microsoft Store certification doesn't see a "crash at
/// launch") and gives the user a readable error instead of a black window.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({this.mediaKitError, this.dbError});

  final Object? mediaKitError;
  final Object? dbError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Karaoke-Chan could not start',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A required component failed to initialize. Please '
                    'reinstall the app or contact support if the problem '
                    'persists.',
                  ),
                  const SizedBox(height: 24),
                  if (dbError != null) ...[
                    const Text('Database error:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText('$dbError'),
                    const SizedBox(height: 12),
                  ],
                  if (mediaKitError != null) ...[
                    const Text('Media engine error:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText('$mediaKitError'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedPlatformApp extends StatelessWidget {
  const _UnsupportedPlatformApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Karaoke-Chan is not available on the web.\n\n'
              'Please install the desktop or mobile app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
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
