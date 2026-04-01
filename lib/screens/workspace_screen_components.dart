part of 'workspace_screen.dart';

// ─── Screen lock toggle button ────────────────────────────────────────────────

class _WorkspaceScreenLockButton extends ConsumerWidget {
  const _WorkspaceScreenLockButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keepOn = ref.watch(settingsProvider).keepScreenOn;
    return Tooltip(
      message: keepOn ? 'Screen lock: off' : 'Screen lock: on',
      child: IconButton(
        isSelected: keepOn,
        icon: const Icon(Icons.screen_lock_portrait_outlined),
        selectedIcon: const Icon(Icons.screen_lock_portrait),
        style: keepOn
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              )
            : null,
        onPressed: () => ref
            .read(settingsProvider.notifier)
            .setKeepScreenOn(!keepOn),
      ),
    );
  }
}

// ─── Resize divider ───────────────────────────────────────────────────────────

class _ResizeDivider extends StatelessWidget {
  final void Function(double delta) onDrag;

  const _ResizeDivider({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 5,
          color: Colors.transparent,
          child: VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.dividerColor,
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final StorageLocation? workspace;
  final VoidCallback onNewFile;

  const _EmptyState({required this.workspace, required this.onNewFile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 20),
            Text(
              'No file open',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              workspace != null
                  ? 'Select a file from the sidebar or create a new one.'
                  : 'Create a new pattern to get started.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onNewFile,
              icon: const Icon(Icons.add),
              label: const Text('New Pattern'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                textStyle: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared popup menu row ────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _MenuRow({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ─── Keyboard shortcuts reference ─────────────────────────────────────────────

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static const _sections = [
    (
      'Modes',
      [
        ('D', 'Draw mode'),
        ('E', 'Erase mode'),
        ('P  or  Space', 'Pan / navigate'),
        ('C', 'Colour picker'),
        ('S', 'Select mode'),
      ]
    ),
    (
      'Stitch Tools  (draw mode)',
      [
        ('1', 'Full stitch'),
        ('2', 'Half stitch  /'),
        ('3', 'Half stitch  \\'),
        ('4', 'Half-cell cross'),
        ('5', 'Quarter diagonal'),
        ('6', 'Quarter-cell cross'),
        ('7', 'Backstitch'),
      ]
    ),
    (
      'Edit',
      [
        ('⌘ Z', 'Undo'),
        ('⌘ ⇧ Z', 'Redo'),
        ('⌘ A', 'Select all'),
        ('⌘ C', 'Copy selection'),
        ('⌘ V', 'Paste'),
        ('⌫  or  Del', 'Delete selection'),
        ('Esc', 'Cancel / deselect'),
      ]
    ),
    (
      'File',
      [
        ('⌘ S', 'Save'),
      ]
    ),
    (
      'PDF viewer',
      [
        ('⌘ =', 'Zoom in'),
        ('⌘ −', 'Zoom out'),
      ]
    ),
    (
      'Stitch mode',
      [
        ('P  or  Space', 'Pan'),
        ('S', 'Select'),
        ('Esc', 'Exit stitch mode'),
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (heading, rows) in _sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(
                    heading,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.primary),
                  ),
                ),
                for (final (key, desc) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            key,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(desc,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ─── Import format banner ────────────────────────────────────────────────────

class _ImportBanner extends StatelessWidget {
  final String filePath;
  final VoidCallback onSaveAs;

  const _ImportBanner({required this.filePath, required this.onSaveAs});

  String get _ext {
    final dot = filePath.lastIndexOf('.');
    return dot >= 0 ? filePath.substring(dot + 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Imported $_ext file — snippets and Drive sync require .stitches format.',
                style: TextStyle(
                    fontSize: 12, color: cs.onTertiaryContainer),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onTertiaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSaveAs,
              child: const Text('Save As .stitches',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
