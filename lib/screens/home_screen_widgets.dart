part of 'home_screen.dart';

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        letterSpacing: 1.0,
      ),
    );
  }
}

// ─── Cached thumbnail image ────────────────────────────────────────────────────

class _CachedThumbnailImage extends StatefulWidget {
  final String thumbnailKey;
  final double width;
  final double height;
  final double borderRadius;

  const _CachedThumbnailImage({
    required this.thumbnailKey,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<_CachedThumbnailImage> createState() => _CachedThumbnailImageState();
}

class _CachedThumbnailImageState extends State<_CachedThumbnailImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ThumbnailCache.load(widget.thumbnailKey).then((bytes) {
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.primaryContainer,
        child: _loaded && _bytes != null
            ? Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                width: widget.width,
                height: widget.height,
              )
            : Icon(
                Icons.grid_4x4,
                size: widget.width * 0.45,
                color: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.5),
              ),
      ),
    );
  }
}

// ─── Folder thumbnail strip ────────────────────────────────────────────────────

class _FolderThumbnailStrip extends StatelessWidget {
  final List<String> thumbnailKeys;

  const _FolderThumbnailStrip({required this.thumbnailKeys});

  @override
  Widget build(BuildContext context) {
    final keys = thumbnailKeys.take(4).toList();
    // Each 40px thumbnail is offset 12px from the previous.
    final w = 40.0 + (keys.length - 1) * 12.0;
    return SizedBox(
      width: w,
      height: 40,
      child: Stack(
        children: [
          for (int i = 0; i < keys.length; i++)
            Positioned(
              left: i * 12.0,
              child: _CachedThumbnailImage(
                thumbnailKey: keys[i],
                width: 40,
                height: 40,
                borderRadius: 6,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── HOME item (mobile only) ──────────────────────────────────────────────────

class _HomeItem extends ConsumerWidget {
  final String homePath;
  final VoidCallback onTap;

  const _HomeItem({required this.homePath, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentItemsProvider);

    final homeThumbnailKeys = recents
        .where((r) =>
            !r.isFolder &&
            !r.isDrive &&
            r.thumbnailKey != null &&
            r.id.startsWith(homePath))
        .take(4)
        .map((r) => r.thumbnailKey!)
        .toList()
        .reversed
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              homeThumbnailKeys.isNotEmpty
                  ? _FolderThumbnailStrip(thumbnailKeys: homeThumbnailKeys)
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.folder_outlined,
                          size: 22,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Local Patterns',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'HOME',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Built-in app storage',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Open modal ───────────────────────────────────────────────────────────────

class _OpenModal extends StatefulWidget {
  final bool driveConnected;
  final bool driveConfigured;
  final String? driveEmail;
  /// Unified picker (macOS): opens NSOpenPanel for both files and folders.
  final VoidCallback onOpenLocal;
  final VoidCallback onOpenLocalFile;
  final VoidCallback onOpenLocalFolder;
  /// Unified Drive picker: handles both files and folders.
  final VoidCallback onOpenDrive;
  final VoidCallback onConnectDrive;

  const _OpenModal({
    required this.driveConnected,
    required this.driveConfigured,
    this.driveEmail,
    required this.onOpenLocal,
    required this.onOpenLocalFile,
    required this.onOpenLocalFolder,
    required this.onOpenDrive,
    required this.onConnectDrive,
  });

  @override
  State<_OpenModal> createState() => _OpenModalState();
}

class _OpenModalState extends State<_OpenModal> {
  bool _localExpanded = false;

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar.
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text('Open',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Local row — on macOS a single unified picker handles both files and
          // folders; on other platforms the accordion expands to show two options.
          if (!kIsWeb && Platform.isMacOS)
            _SourceRow(
              icon: Icons.folder_outlined,
              label: 'Open\u2026',
              subtitle: 'File or folder on this Mac',
              expanded: false,
              onTap: () {
                _dismiss();
                widget.onOpenLocal();
              },
              subRows: const [],
            )
          else
            _SourceRow(
              icon: Icons.folder_outlined,
              label: 'Local',
              subtitle: 'Files & folders on this device',
              expanded: _localExpanded,
              onTap: () => setState(() {
                _localExpanded = !_localExpanded;
              }),
              subRows: [
                _SubRow(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'File',
                  onTap: () {
                    _dismiss();
                    widget.onOpenLocalFile();
                  },
                ),
                _SubRow(
                  icon: Icons.folder_open_outlined,
                  label: 'Folder',
                  onTap: () {
                    _dismiss();
                    widget.onOpenLocalFolder();
                  },
                ),
              ],
            ),

          if (widget.driveConfigured) ...[
            const SizedBox(height: 10),
            _SourceRow(
              icon: Icons.cloud_outlined,
              label: 'Google Drive',
              subtitle: widget.driveConnected
                  ? (widget.driveEmail ?? 'Connected')
                  : 'Sign in to access',
              subtitleColor: widget.driveConnected
                  ? Colors.green.shade600
                  : null,
              expanded: false,
              onTap: () {
                _dismiss();
                if (widget.driveConnected) {
                  widget.onOpenDrive();
                } else {
                  widget.onConnectDrive();
                }
              },
              subRows: const [],
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? subtitleColor;
  final bool expanded;
  final VoidCallback onTap;
  final List<Widget> subRows;

  const _SourceRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.subtitleColor,
    required this.expanded,
    required this.onTap,
    required this.subRows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 22,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11,
                              color: subtitleColor ?? Colors.grey.shade500)),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 4),
            child: Column(children: subRows),
          ),
      ],
    );
  }
}

class _SubRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
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

    // Derive folder thumbnail keys from other recents.
    final allRecents = ref.watch(recentItemsProvider);
    Widget leading;
    if (!item.isFolder && item.thumbnailKey != null) {
      // File with thumbnail — overlay a Drive badge if needed.
      final thumb = _CachedThumbnailImage(
        thumbnailKey: item.thumbnailKey!,
        width: 40,
        height: 40,
      );
      leading = item.isDrive
          ? Stack(children: [
              thumb,
              Positioned(
                right: 2,
                bottom: 2,
                child: _TypeBadge(
                    isFolder: false, isDrive: true, theme: theme),
              ),
            ])
          : thumb;
    } else if (item.isFolder) {
      // Collect up to 3 child thumbnails. allRecents is most-recent-first so
      // we reverse before passing to the strip — the most-recent key ends up
      // last in the Stack and is therefore rendered on top.
      final folderKeys = allRecents
          .where((r) =>
              !r.isFolder &&
              r.thumbnailKey != null &&
              (r.id.startsWith(item.id) || r.parentId == item.id))
          .take(3)
          .map((r) => r.thumbnailKey!)
          .toList()
          .reversed
          .toList();
      if (folderKeys.isNotEmpty) {
        // Folder with thumbnail strip — overlay folder + optional Drive badge.
        leading = Stack(children: [
          _FolderThumbnailStrip(thumbnailKeys: folderKeys),
          Positioned(
            right: 2,
            bottom: 2,
            child: _TypeBadge(
                isFolder: true, isDrive: item.isDrive, theme: theme),
          ),
        ]);
      } else {
        // No thumbnails yet — _RecentIcon already shows folder/Drive icons.
        leading = _RecentIcon(item: item, theme: theme);
      }
    } else {
      leading = _RecentIcon(item: item, theme: theme);
    }

    return Opacity(
      opacity: driveWarning != null ? 0.55 : 1.0,
      child: InkWell(
        onTap: effectiveOnTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 40, child: leading),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    driveWarning != null
                        ? Row(
                            children: [
                              Icon(Icons.warning_amber_outlined,
                                  size: 11,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  driveWarning,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange.shade700),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            item.displayPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(item.relativeTime,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400)),
              const SizedBox(width: 4),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close,
                      size: 14, color: Colors.grey.shade400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentIcon extends StatelessWidget {
  final RecentItem item;
  final ThemeData theme;

  const _RecentIcon({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child:
                  Icon(Icons.cloud, size: 10, color: theme.colorScheme.primary),
            ),
        ],
      ),
    );
  }
}

/// Small pill badge overlaid on thumbnails to indicate folder and/or Drive.
/// At least one of [isFolder]/[isDrive] should be true.
class _TypeBadge extends StatelessWidget {
  final bool isFolder;
  final bool isDrive;
  final ThemeData theme;

  const _TypeBadge({
    required this.isFolder,
    required this.isDrive,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFolder)
            Icon(Icons.folder_outlined,
                size: 10, color: theme.colorScheme.onSurfaceVariant),
          if (isFolder && isDrive) const SizedBox(width: 2),
          if (isDrive)
            Icon(Icons.cloud_outlined,
                size: 10, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}
