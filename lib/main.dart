// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:karaoke_chan/core/database/database_helper.dart';
import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';

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

class KaraokeApp extends ConsumerWidget {
  const KaraokeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Karaoke Chan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
