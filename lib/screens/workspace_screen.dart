import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../data/dmc_colors.dart';
import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor_provider.dart';
import '../providers/file_loading_provider.dart';
import '../providers/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/pdf_viewer_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../services/pdf_service.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/file_sidebar.dart';
import '../widgets/pattern_canvas.dart';
import '../widgets/pdf_viewer_panel.dart';
import 'new_pattern_dialog.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  Timer? _autoSaveTimer;
  final _pdfPanelKey = GlobalKey<PdfViewerPanelState>();

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _save(context, quiet: true);
    });
  }

  // ─── Helpers (mirrored from EditorScreen) ─────────────────────────────────

  CrossStitchPattern _patternWithEditorState(EditorState state) {
    return state.pattern.copyWith(
      editorSelectedThreadId: state.selectedThreadId,
      editorTool: state.currentTool.name,
    );
  }

  Future<void> _save(BuildContext context, {bool quiet = false}) async {
    final state = ref.read(editorProvider);
    try {
      if (state.filePath != null) {
        await FileService.saveFile(
            _patternWithEditorState(state), state.filePath!);
        ref.read(editorProvider.notifier).markSaved();
        if (!quiet && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved')),
          );
        }

        // Auto-upload to Drive if this file is Drive-backed
        final driveFileId = state.driveFileId;
        final parentFolderId = state.driveParentFolderId;
        if (driveFileId != null && parentFolderId != null) {
          final notifier = ref.read(googleDriveProvider.notifier);
          await notifier.uploadPattern(
            _patternWithEditorState(state),
            driveFileId,
            parentFolderId,
          );
        }
      } else {
        await _saveAs(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _saveAs(BuildContext context) async {
    final state = ref.read(editorProvider);
    try {
      final path =
          await FileService.saveFileAs(_patternWithEditorState(state));
      if (path != null) {
        ref.read(editorProvider.notifier).setFilePath(path);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  /// Flushes any pending auto-save immediately before navigating away.
  Future<bool> _onWillPop(BuildContext context) async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final state = ref.read(editorProvider);
    if (state.isDirty && state.isFileOpen) {
      await _save(context, quiet: true);
    }
    ref.read(editorProvider.notifier).closeFile();
    ref.read(pdfViewerProvider.notifier).set(null);
    return true;
  }

  String _title(EditorState editorState, WorkspaceState wsState, OpenPdf? openPdf) {
    if (openPdf != null) {
      return openPdf.title;
    }
    if (editorState.filePath != null || editorState.pattern.name != 'Untitled') {
      final name = editorState.pattern.name;
      final dirty = editorState.isDirty ? ' •' : '';
      return '$name$dirty';
    }
    return wsState.workspace?.displayName ?? 'Workspace';
  }

  Future<void> _newFileInWorkspace(
      BuildContext context, StorageLocation? workspace) async {
    final pattern = await showDialog<CrossStitchPattern>(
      context: context,
      builder: (_) => const NewPatternDialog(),
    );
    if (pattern == null || !context.mounted) return;

    if (workspace is LocalFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final filePath =
          '${workspace.path}${Platform.pathSeparator}$safeName.stitchx';
      try {
        await FileService.saveFile(pattern, filePath);
        ref.read(pdfViewerProvider.notifier).set(null);
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: filePath);
        refreshFolder(ref, workspace);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create file: $e'),
                backgroundColor: Colors.red.shade700),
          );
        }
      }
    } else if (workspace is DriveFolder) {
      final safeName = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final fileName = '$safeName.stitchx';
      ref.read(fileLoadingProvider.notifier).set(true);
      try {
        // Write to temp and open immediately — Drive upload happens in background.
        final tempDir = await getTemporaryDirectory();
        await Directory(tempDir.path).create(recursive: true);
        final tempPath = '${tempDir.path}/$fileName';
        await FileService.saveFile(pattern, tempPath);

        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveParentFolderId: workspace.folderId,
          // driveFileId left null — set after background upload.
        );

        // Show the file in the sidebar tree immediately via a placeholder.
        addPendingDriveFile(
          ref,
          workspace.folderId,
          DrivePatternFile(
            fileId: tempPath, // placeholder — replaced once upload completes
            name: fileName,
            parentFolder: workspace,
            modified: DateTime.now(),
          ),
        );

        unawaited(_uploadNewFileToDrive(workspace, pattern, tempPath));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create file: $e'),
                backgroundColor: Colors.red.shade700),
          );
        }
      } finally {
        if (mounted) ref.read(fileLoadingProvider.notifier).set(false);
      }
    } else {
      // No workspace — fall back to standalone new pattern
      ref.read(editorProvider.notifier).newPattern(pattern);
    }
  }

  Future<void> _uploadNewFileToDrive(
      DriveFolder folder, CrossStitchPattern pattern, String tempPath) async {
    final newFileId = await ref.read(googleDriveProvider.notifier).uploadPattern(
      pattern, null, folder.folderId);
    if (!mounted) return;
    // Remove the optimistic placeholder before refreshing from Drive.
    clearPendingDriveFiles(ref, folder.folderId);
    if (newFileId != null) {
      ref.read(editorProvider.notifier).setDriveFileId(newFileId);
      refreshFolder(ref, folder);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload file to Drive.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context, EditorState state) async {
    try {
      await PdfService.exportPattern(state.pattern);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('PDF export failed: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _showResizeDialog(
      BuildContext context, EditorState state) async {
    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (_) => ResizeCanvasDialog(
        currentWidth: state.pattern.width,
        currentHeight: state.pattern.height,
      ),
    );
    if (result == null) return;
    ref.read(editorProvider.notifier).resizePattern(
          result.width,
          result.height,
          result.anchorX,
          result.anchorY,
        );
  }

  void _showPatternInfo(BuildContext context, EditorState state) {
    final p = state.pattern;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pattern Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('Name', p.name),
            _InfoRow('Size', '${p.width} × ${p.height} stitches'),
            _InfoRow('Threads', '${p.threads.length}'),
            _InfoRow('Stitches', '${p.stitches.length}'),
            if (state.filePath != null)
              _InfoRow('File', state.filePath!.split('/').last),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'))
        ],
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final wsState = ref.watch(workspaceProvider);
    final driveState = ref.watch(googleDriveProvider);
    final isFileLoading = ref.watch(fileLoadingProvider);
    final openPdf = ref.watch(pdfViewerProvider);

    // ── Auto-save listener ────────────────────────────────────────────────
    ref.listen<EditorState>(editorProvider, (prev, next) {
      if (!next.isDirty || !next.isFileOpen) return;
      _scheduleAutoSave();
    });

    // ── Keyboard handler (identical to EditorScreen) ─────────────────────
    KeyEventResult handleKeys(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }

      final notifier = ref.read(editorProvider.notifier);
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
      final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight);

      final key = event.logicalKey;

      // In stitch mode: allow pan/select mode toggle and Escape.
      if (editorState.stitchMode) {
        if (key == LogicalKeyboardKey.keyS) {
          notifier.setDrawingMode(DrawingMode.select);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyP ||
            key == LogicalKeyboardKey.space) {
          notifier.setDrawingMode(DrawingMode.pan);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          if (editorState.selectionRect != null) {
            notifier.cancelSelection();
          } else {
            notifier.toggleStitchMode();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // PDF zoom shortcuts (Cmd+= / Cmd+-)
      if (openPdf != null && (meta || ctrl)) {
        if (key == LogicalKeyboardKey.equal) {
          _pdfPanelKey.currentState?.zoomIn();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.minus) {
          _pdfPanelKey.currentState?.zoomOut();
          return KeyEventResult.handled;
        }
      }

      // Modifier shortcuts
      if (meta || ctrl) {
        if (key == LogicalKeyboardKey.keyZ && !shift) {
          notifier.undo();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyZ && shift) {
          notifier.redo();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyY) {
          notifier.redo();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyA) {
          notifier.selectAll();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyC) {
          notifier.copySelection();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyV) {
          notifier.enterPasteMode();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // Single-key shortcuts
      switch (key) {
        case LogicalKeyboardKey.keyD:
          notifier.setDrawingMode(DrawingMode.draw);
        case LogicalKeyboardKey.keyE:
          notifier.setDrawingMode(DrawingMode.erase);
        case LogicalKeyboardKey.keyP:
          notifier.setDrawingMode(DrawingMode.pan);
        case LogicalKeyboardKey.space:
          notifier.setDrawingMode(DrawingMode.pan);
        case LogicalKeyboardKey.digit1:
          notifier.setTool(DrawingTool.fullStitch);
        case LogicalKeyboardKey.digit2:
          notifier.setTool(DrawingTool.halfForward);
        case LogicalKeyboardKey.digit3:
          notifier.setTool(DrawingTool.halfBackward);
        case LogicalKeyboardKey.digit4:
          notifier.setTool(DrawingTool.halfCross);
        case LogicalKeyboardKey.digit5:
          notifier.setTool(DrawingTool.quarterDiag);
        case LogicalKeyboardKey.digit6:
          notifier.setTool(DrawingTool.quarterCross);
        case LogicalKeyboardKey.digit7:
          notifier.setTool(DrawingTool.backstitch);
        case LogicalKeyboardKey.keyC:
          notifier.setDrawingMode(DrawingMode.colorPicker);
        case LogicalKeyboardKey.keyS:
          notifier.setDrawingMode(DrawingMode.select);
        case LogicalKeyboardKey.escape:
          notifier.cancelSelection();
        case LogicalKeyboardKey.delete:
        case LogicalKeyboardKey.backspace:
          notifier.deleteSelection();
        case LogicalKeyboardKey.slash:
          if (shift) {
            showDialog(
                context: context,
                builder: (_) => const _ShortcutsDialog());
          } else {
            return KeyEventResult.ignored;
          }
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(context);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title(editorState, wsState, openPdf)),
          backgroundColor: editorState.stitchMode
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          actions: [
            // PDF viewer actions
            if (openPdf != null) ...[
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: 'Zoom out',
                onPressed: () => _pdfPanelKey.currentState?.zoomOut(),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: 'Zoom in',
                onPressed: () => _pdfPanelKey.currentState?.zoomIn(),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: ref.watch(settingsProvider).keepScreenOn,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOn(v ?? false),
                  ),
                  const Text('Keep screen on', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ],
              ),
            ],
            if (editorState.isFileOpen && !editorState.stitchMode && openPdf == null) ...[
              // Drive sync indicator — shown as soon as the file has a Drive
              // parent, including while the initial upload is still pending
              // (driveFileId == null but driveParentFolderId != null).
              if (editorState.driveParentFolderId != null)
                Tooltip(
                  message: (driveState.isSyncing ||
                          editorState.driveFileId == null)
                      ? 'Syncing to Google Drive…'
                      : 'Synced to Google Drive',
                  child: (driveState.isSyncing ||
                          editorState.driveFileId == null)
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.cloud_done_outlined),
                ),
              IconButton(
                icon: const Icon(Icons.save_as_outlined),
                tooltip: 'Save As…',
                onPressed: () => _saveAs(context),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export PDF…',
                onPressed: () => _exportPdf(context, editorState),
              ),
              IconButton(
                icon: const Icon(Icons.crop_outlined),
                tooltip: 'Resize Aida',
                onPressed: () =>
                    _showResizeDialog(context, editorState),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Pattern Info',
                onPressed: () => _showPatternInfo(context, editorState),
              ),
              IconButton(
                icon: Icon(
                  editorState.referenceImage != null
                      ? Icons.photo_filter
                      : Icons.photo_filter_outlined,
                  color: editorState.referenceImage != null &&
                          editorState.referenceVisible
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: 'Reference Image',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ReferenceImageSheet(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_outlined),
                tooltip: 'Keyboard Shortcuts (?)',
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _ShortcutsDialog()),
              ),
            ],
            // Keep screen on — only shown in stitch mode with a file open
            if (editorState.isFileOpen && editorState.stitchMode && openPdf == null) ...[
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: ref.watch(settingsProvider).keepScreenOn,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOn(v ?? false),
                  ),
                  const Text('Keep screen on',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ],
              ),
            ],
            // Stitch mode toggle — only visible with a file open
            if (editorState.isFileOpen && openPdf == null)
              Tooltip(
                message: editorState.stitchMode
                    ? 'Exit Stitch Mode'
                    : 'Stitch Mode',
                child: Switch(
                  value: editorState.stitchMode,
                  onChanged: (_) =>
                      ref.read(editorProvider.notifier).toggleStitchMode(),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar
                if (wsState.sidebarVisible) ...[
                  const FileSidebar(),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                // Editor, PDF viewer, or empty state
                Expanded(
                  child: openPdf != null
                      ? Focus(
                          autofocus: true,
                          onKeyEvent: handleKeys,
                          child: PdfViewerPanel(key: _pdfPanelKey, path: openPdf.localPath),
                        )
                      : editorState.isFileOpen
                          ? Focus(
                              autofocus: true,
                              onKeyEvent: handleKeys,
                              child: const Column(
                                children: [
                                  Expanded(child: PatternCanvas()),
                                  EditorToolbar(),
                                ],
                              ),
                            )
                          : _EmptyState(
                              workspace: wsState.workspace,
                              onNewFile: () => _newFileInWorkspace(
                                  context, wsState.workspace),
                            ),
                ),
              ],
            ),
            // Blocking loading overlay (Drive download in progress)
            if (isFileLoading)
              const Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),

            // Open-sidebar tab (visible only when sidebar is hidden)
            if (!wsState.sidebarVisible)
              Positioned(
                left: 0,
                top: 12,
                child: Material(
                  elevation: 2,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: InkWell(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    onTap: () =>
                        ref.read(workspaceProvider.notifier).toggleSidebar(),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Tooltip(
                        message: 'Open sidebar',
                        child: Icon(Icons.chevron_right, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        endDrawer: (editorState.isFileOpen && openPdf == null) ? const _StitchPalettePanel() : null,
        endDrawerEnableOpenDragGesture: false,
      ),
    );
  }
}

// ─── Stitch mode palette side panel ──────────────────────────────────────────
// (identical to the one in editor_screen.dart)

class _StitchPalettePanel extends ConsumerWidget {
  const _StitchPalettePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final threads = state.pattern.threads;
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text('Threads', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No threads yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: threads.length,
                  itemBuilder: (_, i) {
                    final t = threads[i];
                    final displayCode = useDmc
                        ? t.dmcCode
                        : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
                    final textColor = t.color.computeLuminance() > 0.35
                        ? Colors.black
                        : Colors.white;
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.grey.shade400, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: t.symbol.isNotEmpty
                            ? Text(
                                t.symbol,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.0,
                                ),
                              )
                            : null,
                      ),
                      title: Text('$displayCode – ${t.name}',
                          style: const TextStyle(fontSize: 13)),
                    );
                  },
                ),
              ),
          ],
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

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
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
