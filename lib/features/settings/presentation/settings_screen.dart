// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

const _bg = Color(0xFF111827);
const _cardBg = Color(0xFF1F2937);
const _border = Color(0xFF374151);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _cardBg,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Library ──────────────────────────────────────────────
          const _SectionLabel(label: 'Library'),
          const Gap(8),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.folder_open,
                iconColor: AppTheme.primary,
                title: 'Change Karaoke Folder',
                subtitle: 'Pick a different root folder to scan',
                onTap: () => ref.read(libraryProvider.notifier).changeFolder(),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.radar,
                iconColor: AppTheme.primary,
                title: 'Re-scan Folder',
                subtitle: 'Update library with new or deleted files',
                onTap: () => ref.read(libraryProvider.notifier).scanFolder(),
              ),
            ],
          ),
          const Gap(24),

          // ── Queue ────────────────────────────────────────────────
          const _SectionLabel(label: 'Queue'),
          const Gap(8),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.cleaning_services,
                iconColor: AppTheme.error,
                title: 'Clear Queue',
                subtitle: 'Remove all waiting and playing entries',
                onTap: () => _confirmClearQueue(context, ref),
              ),
            ],
          ),
          const Gap(24),

          // ── About ────────────────────────────────────────────────
          const _SectionLabel(label: 'About'),
          const Gap(8),
          const _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.mic,
                iconColor: AppTheme.primary,
                title: 'Karaoke Chan',
                subtitle: 'Version 1.0.0 — Cross-platform offline karaoke',
              ),
              _Divider(),
              _SettingsTile(
                icon: Icons.devices,
                iconColor: AppTheme.secondary,
                title: 'Platform Support',
                subtitle: 'Android · macOS · Windows',
              ),
            ],
          ),
          const Gap(40),
        ],
      ),
    );
  }

  void _confirmClearQueue(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title:
            const Text('Clear Queue?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove all entries from the queue.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(queueNotifierProvider.notifier).clearAll();
            },
            child: const Text('Clear', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: _border);
  }
}
