part of 'workspace_screen.dart';

// ─── Running-timer banner ─────────────────────────────────────────────────────

/// Banner shown at the top of the workspace when a timer is running for a
/// pattern that is not currently open. Live-updates elapsed time every second
/// (driven by [StitchingTimerState.tickCount] via the parent's ref.watch).
class _TimerBanner extends StatelessWidget {
  final StitchingTimerState timerState;
  final VoidCallback onDismiss;
  final VoidCallback onStop;
  final VoidCallback onOpen;

  const _TimerBanner({
    required this.timerState,
    required this.onDismiss,
    required this.onStop,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = timerState.timerPatternName ??
        timerState.timerFilePath!.split(Platform.pathSeparator).last;
    final session = fmtDuration(timerState.elapsed);
    final colorScheme = Theme.of(context).colorScheme;
    final fg = colorScheme.onSecondaryContainer;

    return ColoredBox(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$displayName — $session',
                style: TextStyle(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            TextButton(
                onPressed: onStop, child: const Text('Stop & discard')),
            const SizedBox(width: 4),
            FilledButton(
                onPressed: onOpen,
                child: const Text('Open in stitch mode')),
          ],
        ),
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
          color: theme.colorScheme.surface,
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
            Builder(builder: (context) {
              final isPhone =
                  MediaQuery.of(context).size.shortestSide < 600;
              if (isPhone) {
                return FilledButton(
                  onPressed: onNewFile,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    textStyle: theme.textTheme.titleSmall,
                  ),
                  child: const Text('+'),
                );
              }
              return FilledButton.icon(
                onPressed: onNewFile,
                icon: const Icon(Icons.add),
                label: const Text('New Pattern'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  textStyle: theme.textTheme.titleSmall,
                ),
              );
            }),
          ],
        ),
      ),
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

