part of 'home_screen.dart';

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _SectionLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        letterSpacing: 1.0,
      ),
    );
    if (trailing == null) return labelText;
    return Row(
      children: [
        labelText,
        const SizedBox(width: 8),
        trailing!,
      ],
    );
  }
}

// ─── Open button ──────────────────────────────────────────────────────────────

class _OpenButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool cloudBadge;
  final VoidCallback? onTap;

  const _OpenButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.cloudBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 18),
              if (cloudBadge)
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: Icon(Icons.cloud, size: 10,
                      color: theme.colorScheme.primary),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

// ─── Recent section (expandable) ──────────────────────────────────────────────

class _RecentSection extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<RecentItem> items;
  final void Function(RecentItem)? onTap;
  final void Function(RecentItem) onRemove;

  const _RecentSection({
    required this.label,
    required this.icon,
    required this.items,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_RecentSection> createState() => _RecentSectionState();
}

class _RecentSectionState extends State<_RecentSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Icon(widget.icon,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.items.length}',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.items.map((item) => _RecentItemTile(
                item: item,
                onTap: widget.onTap != null ? () => widget.onTap!(item) : null,
                onRemove: () => widget.onRemove(item),
              )),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Recent item tile ─────────────────────────────────────────────────────────

class _RecentItemTile extends ConsumerWidget {
  final RecentItem item;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  const _RecentItemTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  String? _driveWarning(DriveState driveState) {
    if (!item.isDrive) return null;
    if (driveState.status != DriveStatus.connected) {
      return 'Not signed in to Google Drive';
    }
    if (item.driveEmail != null &&
        driveState.email != null &&
        item.driveEmail != driveState.email) {
      return 'Not available — saved to ${item.driveEmail}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final driveWarning = _driveWarning(ref.watch(googleDriveProvider));
    final effectiveOnTap = driveWarning != null ? null : onTap;

    return Opacity(
      opacity: driveWarning != null ? 0.55 : 1.0,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                item.isFolder
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              if (item.isDrive)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(Icons.cloud,
                      size: 10, color: theme.colorScheme.primary),
                ),
            ],
          ),
        ),
        title: Text(
          item.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: driveWarning != null
            ? Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 11, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      driveWarning,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade700),
                    ),
                  ),
                ],
              )
            : Text(
                item.displayPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.relativeTime,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close, size: 14, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        onTap: effectiveOnTap,
      ),
    );
  }
}
