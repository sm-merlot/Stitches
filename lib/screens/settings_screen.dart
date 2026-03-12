import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

// Common aida fabric colours.
const _aidaPresets = [
  (label: 'White',       color: Color(0xFFFFFFFF)),
  (label: 'Antique white', color: Color(0xFFFAF0DC)),
  (label: 'Cream',       color: Color(0xFFFFF8DC)),
  (label: 'Light grey',  color: Color(0xFFD8D8D8)),
  (label: 'Mid grey',    color: Color(0xFF888888)),
  (label: 'Charcoal',    color: Color(0xFF404040)),
  (label: 'Black',       color: Color(0xFF1A1A1A)),
  (label: 'Navy',        color: Color(0xFF1B2A4A)),
  (label: 'Sage green',  color: Color(0xFF7A9E7E)),
  (label: 'Sky blue',    color: Color(0xFFB0C8E0)),
  (label: 'Dusty rose',  color: Color(0xFFD4A0A0)),
  (label: 'Burgundy',    color: Color(0xFF6B1A1A)),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
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
          const _SectionHeader('Display'),
          SwitchListTile(
            title: const Text('Keep screen on'),
            subtitle: const Text('Prevents screen from sleeping while editing'),
            secondary: const Icon(Icons.brightness_high_outlined),
            value: settings.keepScreenOn,
            onChanged: (v) => notifier.setKeepScreenOn(v),
          ),
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Aida fabric colour'),
            subtitle: const Text('Background colour of the canvas grid'),
            trailing: GestureDetector(
              onTap: () => _showAidaColorPicker(context, ref, settings.aidaColor),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: settings.aidaColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
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

void _showAidaColorPicker(BuildContext context, WidgetRef ref, Color current) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Aida fabric colour'),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _aidaPresets.map((p) {
          final selected = p.color.toARGB32() == current.toARGB32();
          return Tooltip(
            message: p.label,
            child: GestureDetector(
              onTap: () {
                ref.read(settingsProvider.notifier).setAidaColor(p.color);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: p.color.computeLuminance() > 0.4
                            ? Colors.black54
                            : Colors.white70,
                      )
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
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
