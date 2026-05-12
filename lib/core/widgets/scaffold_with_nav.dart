// lib/core/widgets/scaffold_with_nav.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:karaoke_chan/core/router/app_router.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';

class ScaffoldWithNav extends StatelessWidget {
  const ScaffoldWithNav({super.key, required this.child});

  final Widget child;

  int _locationToIndex(String location) {
    if (location.startsWith(AppRoutes.queue)) return 1;
    if (location.startsWith(AppRoutes.library)) return 2;
    if (location.startsWith(AppRoutes.settings)) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
      case 1:
        context.go(AppRoutes.queue);
      case 2:
        context.go(AppRoutes.library);
      case 3:
        context.go(AppRoutes.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _locationToIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: _KaraokeNavBar(
        currentIndex: index,
        onTap: (i) => _onTap(context, i),
      ),
    );
  }
}

class _KaraokeNavBar extends StatelessWidget {
  const _KaraokeNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A4A), width: 1)),
      ),
      child: NavigationBar(
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withOpacity(0.15),
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppTheme.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music, color: AppTheme.primary),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music, color: AppTheme.primary),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppTheme.primary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
