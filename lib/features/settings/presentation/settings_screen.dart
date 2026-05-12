// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:karaoke_chan/core/services/remote_server.dart';
import 'package:karaoke_chan/core/theme/app_theme.dart';
import 'package:karaoke_chan/core/widgets/neon_card.dart';
import 'package:karaoke_chan/features/library/data/library_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverActive = ref.watch(remoteServerActiveProvider);
    final server = ref.watch(remoteServerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Remote Queue ──────────────────────────────────────────
          const _SectionLabel(label: 'Remote Queue'),
          const Gap(8),
          NeonCard(
            glowColor: serverActive ? AppTheme.secondary : null,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.wifi,
                    color: serverActive ? AppTheme.secondary : Colors.white38,
                  ),
                  title: const Text('Remote Queue Server'),
                  subtitle: Text(
                    serverActive
                        ? 'Phones can add songs via browser'
                        : 'Let guests add songs from their phones',
                    style: TextStyle(
                      color: serverActive
                          ? AppTheme.secondary.withValues(alpha: 0.7)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Switch(
                    value: serverActive,
                    activeThumbColor: AppTheme.secondary,
                    activeTrackColor: AppTheme.secondary.withValues(alpha: 0.3),
                    onChanged: (_) =>
                        ref.read(remoteServerActiveProvider.notifier).toggle(),
                  ),
                ),
                if (serverActive) ...[
                  const Divider(height: 1),
                  FutureBuilder<String?>(
                    future: server.queueUrl,
                    builder: (context, snap) {
                      if (!snap.hasData || snap.data == null) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Could not detect Wi-Fi IP.\nMake sure you are connected to Wi-Fi.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final url = snap.data!;
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'Scan QR code with a phone on the same Wi-Fi',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.white54),
                              textAlign: TextAlign.center,
                            ),
                            const Gap(12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: QrImageView(
                                data: url,
                                version: QrVersions.auto,
                                size: 180,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const Gap(8),
                            SelectableText(
                              url,
                              style: const TextStyle(
                                color: AppTheme.secondary,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const Gap(4),
                            const Text(
                              'Guests open this URL → search songs → tap to add',
                              style: TextStyle(
                                  color: Colors.white30, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const Gap(24),

          // ── Library ───────────────────────────────────────────────
          const _SectionLabel(label: 'Library'),
          const Gap(8),
          NeonCard(
            child: Column(
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.folder_open, color: AppTheme.primary),
                  title: const Text('Change Karaoke Folder'),
                  subtitle: const Text('Pick a different root folder to scan'),
                  onTap: () =>
                      ref.read(libraryProvider.notifier).changeFolder(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.radar, color: AppTheme.primary),
                  title: const Text('Re-scan Folder'),
                  subtitle: const Text('Update library with new/deleted files'),
                  onTap: () => ref.read(libraryProvider.notifier).scanFolder(),
                ),
              ],
            ),
          ),
          const Gap(24),

          // ── Queue ─────────────────────────────────────────────────
          const _SectionLabel(label: 'Queue'),
          const Gap(8),
          NeonCard(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services, color: AppTheme.error),
              title: const Text('Clear Queue'),
              subtitle: const Text('Remove all waiting & playing entries'),
              onTap: () => _confirmClearQueue(context, ref),
            ),
          ),
          const Gap(24),

          // ── About ─────────────────────────────────────────────────
          const _SectionLabel(label: 'About'),
          const Gap(8),
          const NeonCard(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.mic, color: AppTheme.primary),
                  title: Text('Karaoke Chan'),
                  subtitle: Text(
                      'Version 1.0.0 — Cross-platform offline karaoke'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.devices, color: AppTheme.secondary),
                  title: Text('Platform Support'),
                  subtitle: Text('Android · macOS · Windows'),
                ),
              ],
            ),
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
        backgroundColor: AppTheme.surface,
        title: const Text('Clear Queue?'),
        content:
            const Text('This will remove all entries from the queue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(queueNotifierProvider.notifier).clearAll();
            },
            child: const Text('Clear',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

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
