import 'package:flutter/foundation.dart';
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

          // ── Files ─────────────────────────────────────────────────────────
          const _SectionHeader('Files'),
          SwitchListTile(
            title: const Text('Compress new files'),
            subtitle: const Text('New patterns are saved as gzip-compressed .stitchx files. Existing files keep their current format.'),
            secondary: const Icon(Icons.folder_zip_outlined),
            value: settings.compressNewFiles,
            onChanged: (v) => notifier.setCompressNewFiles(v),
          ),
          const Divider(),

          // ── Thread Colours ────────────────────────────────────────────────
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
          if (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux) ...[
            const Divider(),
            const _SectionHeader('Keyboard Shortcuts'),
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
            const _ShortcutTile('Fill colour', '8'),
            const _ShortcutTile('Fill erase', '9'),
            const _ShortcutTile('Colour picker', 'C'),
          ],
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const Divider(),
            const _SectionHeader('Gestures'),
            const ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('Finger double-tap'),
              subtitle: Text('Undo last action'),
            ),
          ],
          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
            const Divider(),
            const _SectionHeader('Apple Pencil'),
            const ListTile(
              leading: Icon(Icons.draw_outlined),
              title: Text('Hardware double-tap'),
              subtitle: Text('Toggles between draw and erase mode'),
            ),
            const ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('Finger double-tap'),
              subtitle: Text('Undo last action'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.content_paste_outlined),
              title: const Text('Pencil-positions, finger-confirms paste'),
              subtitle: const Text(
                  'Hover the pencil to place the ghost, then tap with a finger to stamp.'),
              value: settings.pencilPasteConfirm,
              onChanged: (v) => notifier.setPencilPasteConfirm(v),
            ),
          ],
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
