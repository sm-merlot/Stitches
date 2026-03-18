import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/google_drive_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final driveState = ref.watch(googleDriveProvider);
    final driveNotifier = ref.read(googleDriveProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // ── Google Drive ──────────────────────────────────────────────────
          const _SectionHeader('Google Drive'),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(
              driveState.status == DriveStatus.connected
                  ? (driveState.email == 'connected'
                      ? 'Connected'
                      : driveState.email ?? 'Connected')
                  : 'Not connected',
            ),
            subtitle: driveState.error != null
                ? Text(
                    driveState.error!,
                    style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                  )
                : null,
            trailing: driveState.status == DriveStatus.connecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : driveState.status == DriveStatus.connected
                    ? TextButton(
                        onPressed: () => driveNotifier.disconnect(),
                        child: const Text('Sign Out'),
                      )
                    : FilledButton(
                        onPressed: () => driveNotifier.connect(),
                        child: const Text('Connect'),
                      ),
          ),
          const Divider(),
          const _SectionHeader('Auto-Save'),
          SwitchListTile(
            title: const Text('Auto-save local files'),
            subtitle: const Text('Automatically save after a short pause while editing'),
            secondary: const Icon(Icons.save_outlined),
            value: settings.autoSaveLocal,
            onChanged: (v) => notifier.setAutoSaveLocal(v),
          ),
          const Divider(),
          const _SectionHeader('Thread Colours'),
          SwitchListTile(
            title: const Text('Colour system'),
            subtitle: Text(settings.useDmc ? 'DMC (active)' : 'Anchor (active)'),
            secondary: const Icon(Icons.palette_outlined),
            value: settings.useDmc,
            onChanged: (v) => notifier.setUseDmc(v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Switch between DMC and Anchor thread numbering. '
              'Your pattern stores thread data in both — switching only changes '
              'how colours are labelled.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),
          const _SectionHeader('Keyboard Shortcuts (Desktop)'),
          const _ShortcutTile('Undo', 'Cmd/Ctrl + Z'),
          const _ShortcutTile('Redo', 'Cmd/Ctrl + Shift + Z  or  Cmd/Ctrl + Y'),
          const _ShortcutTile('Draw mode', 'D'),
          const _ShortcutTile('Erase mode', 'E'),
          const _ShortcutTile('Pan mode', 'P  or  Space'),
          const _ShortcutTile('Full cross stitch', '1'),
          const _ShortcutTile('Half diagonal /', '2'),
          const _ShortcutTile('Half diagonal \\', '3'),
          const _ShortcutTile('Half-cell cross (X in ½ cell)', '4'),
          const _ShortcutTile('Quarter diagonal (auto-corner)', '5'),
          const _ShortcutTile('Quarter-cell cross / petit point', '6'),
          const _ShortcutTile('Backstitch', '7'),
          const _ShortcutTile('Colour picker', 'C'),
          const Divider(),
          const _SectionHeader('Apple Pencil'),
          const ListTile(
            leading: Icon(Icons.draw_outlined),
            title: Text('Hardware double-tap'),
            subtitle: Text('Toggles between draw and erase mode'),
          ),
          const ListTile(
            leading: Icon(Icons.touch_app_outlined),
            title: Text('Finger double-tap (iPad / Android)'),
            subtitle: Text('Undo last action'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final String action;
  final String shortcut;
  const _ShortcutTile(this.action, this.shortcut);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(action),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          shortcut,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
