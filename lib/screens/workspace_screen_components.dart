part of 'workspace_screen.dart';

// ─── Running-timer chip (AppBar title area) ───────────────────────────────────

/// Compact chip placed in the AppBar title row whenever a timer is running.
/// Tapping opens a live-updating bottom sheet with stop / open options.
/// Elapsed label is driven by [StitchingTimerState.tickCount] (parent rebuilds
/// via ref.watch every second).
class _TimerChip extends StatelessWidget {
  final StitchingTimerState timerState;
  final DateTime? lastInteractionAt;
  final void Function(DateTime? stopAt) onStop;

  /// Non-null when the running timer belongs to a *different* pattern than the
  /// one currently open — "Open in stitch mode" calls this.
  final VoidCallback? onOpen;

  const _TimerChip({
    required this.timerState,
    required this.lastInteractionAt,
    required this.onStop,
    this.onOpen,
  });

  /// Pattern name, stripping the `.stitches` extension from the file-path
  /// fallback so a bare GDrive cache filename is at least extension-free.
  String? _displayName() {
    if (timerState.timerPatternName != null) return timerState.timerPatternName;
    final base = timerState.timerFilePath?.split(Platform.pathSeparator).last;
    if (base == null) return null;
    return base.endsWith('.stitches')
        ? base.substring(0, base.length - '.stitches'.length)
        : base;
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName();
    final elapsed = fmtDuration(timerState.elapsed);
    final label = name != null ? '$name — $elapsed' : elapsed;
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: ActionChip(
        avatar: Icon(Icons.timer_outlined, size: 16, color: cs.onSecondaryContainer),
        label: Text(
          label,
          style: TextStyle(color: cs.onSecondaryContainer),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: cs.secondaryContainer,
        side: BorderSide.none,
        onPressed: () => _showOptions(context),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    if (timerState.sessionStart == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _TimerChipSheet(
        sessionStart: timerState.sessionStart!,
        timerPatternName: timerState.timerPatternName,
        lastInteractionAt: lastInteractionAt,
        onStop: onStop,
        onOpen: onOpen,
      ),
    );
  }
}

// ─── Live-updating bottom sheet ───────────────────────────────────────────────

class _TimerChipSheet extends StatefulWidget {
  final DateTime sessionStart;
  final String? timerPatternName;
  final DateTime? lastInteractionAt;
  final void Function(DateTime? stopAt) onStop;
  final VoidCallback? onOpen;

  const _TimerChipSheet({
    required this.sessionStart,
    required this.timerPatternName,
    required this.lastInteractionAt,
    required this.onStop,
    this.onOpen,
  });

  @override
  State<_TimerChipSheet> createState() => _TimerChipSheetState();
}

class _TimerChipSheetState extends State<_TimerChipSheet> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = fmtDuration(_now.difference(widget.sessionStart));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.timer_outlined,
                    color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.timerPatternName != null)
                        Text(widget.timerPatternName!,
                            style: Theme.of(context).textTheme.titleMedium),
                      Text(fmtLastActivity(widget.lastInteractionAt, _now),
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('Session: $elapsed',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (widget.onOpen != null)
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Open in stitch mode'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpen!();
              },
            ),
          if (widget.lastInteractionAt != null)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Stop at last activity'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onStop(widget.lastInteractionAt);
              },
            ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('Stop, keep all time'),
            onTap: () {
              Navigator.of(context).pop();
              widget.onStop(null);
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Dismiss'),
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
        ],
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

