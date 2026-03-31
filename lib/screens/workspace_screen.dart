import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pattern.dart';
import '../models/storage_location.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/file_loading_provider.dart';
import '../providers/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../providers/image_viewer_provider.dart';
import '../providers/pdf_viewer_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/file_service.dart';
import '../services/format_service.dart';
import '../utils/snackbars.dart';
import 'export_dialog.dart';
import '../services/grid_detector.dart';
import '../services/grid_symbol_matcher.dart';
import '../services/pdf_scanner.dart';
import 'pattern_scan_symbol_screen.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/file_sidebar.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/right_sidebar_colours_panel.dart';
import '../widgets/pattern_canvas.dart';
import '../widgets/pdf_page_picker.dart';
import '../widgets/image_viewer_panel.dart';
import '../widgets/pdf_viewer_panel.dart';
import 'new_pattern_dialog.dart';
import 'pattern_scan_cell_screen.dart';
import 'pattern_scan_crop_screen.dart';
import 'pattern_scan_preview.dart';
import 'pattern_scan_review_screen.dart';
import 'reference_image_sheet.dart';
import 'resize_canvas_dialog.dart';

part 'workspace_screen_components.dart';

enum _MenuAction { saveAs, export, resize, patternInfo, referenceImage, shortcuts, toggleCompress }

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}


class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  Timer? _autoSaveTimer;
  final _pdfPanelKey = GlobalKey<PdfViewerPanelState>();

  // PDF scan overlay — full-screen Overlay entry so AppBar is also blocked.
  final _scanStatus = ValueNotifier<String?>(null);
  final _scanSubtitle = ValueNotifier<String?>(null);
  bool _scanCancelled = false;
  OverlayEntry? _scanOverlayEntry;

  void _showScanOverlay(BuildContext context, String initialStatus) {
    _scanStatus.value = initialStatus;
    _scanOverlayEntry?.remove();
    _scanOverlayEntry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Full-screen dim absorbs all taps (AppBar, back button, body).
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(color: const Color(0x66000000)),
              ),
            ),
            // Card is a sibling — NOT inside AbsorbPointer — so cancel works.
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<String?>(
                        valueListenable: _scanStatus,
                        builder: (context, status, child) =>
                            Text(status ?? ''),
                      ),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<String?>(
                        valueListenable: _scanSubtitle,
                        builder: (context, subtitle, child) => subtitle != null
                            ? Text(
                                subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          _scanCancelled = true;
                          _removeScanOverlay();
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_scanOverlayEntry!);
  }

  void _removeScanOverlay() {
    _scanStatus.value = null;
    _scanSubtitle.value = null;
    _scanOverlayEntry?.remove();
    _scanOverlayEntry = null;
  }

  @override
  void dispose() {
    // If a pending auto-save timer was cancelled without firing, flush it now.
    if (_autoSaveTimer != null) {
      _autoSaveTimer!.cancel();
      _autoSaveTimer = null;
      final state = ref.read(editorProvider);
      if (state.isDirty && state.filePath != null && state.isNativeFormat) {
        FileService.saveFile(state.patternForSave, state.filePath!,
            compress: state.compressOnSave);
      }
    }
    _scanOverlayEntry?.remove();
    _scanStatus.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _save(context, quiet: true);
    });
  }

  Future<void> _save(BuildContext context, {bool quiet = false}) async {
    final state = ref.read(editorProvider);
    try {
      if (state.filePath != null) {
        // If the open file is in a foreign format, write back in that format.
        if (!state.isNativeFormat) {
          final format = CrossStitchFormat.forPath(state.filePath!);
          if (format != null) {
            await FormatService.exportFile(
                state.patternForSave, state.filePath!, format);
          }
        } else {
          await FileService.saveFile(
              state.patternForSave, state.filePath!,
              compress: state.compressOnSave);
        }
        ref.read(editorProvider.notifier).markSaved();
        if (!quiet && context.mounted) showSuccess(context, 'Saved');

        // Auto-upload to Drive only for native .stitchx files.
        if (state.isNativeFormat) {
          final driveFileId = state.driveFileId;
          final parentFolderId = state.driveParentFolderId;
          if (driveFileId != null && parentFolderId != null) {
            final notifier = ref.read(googleDriveProvider.notifier);
            await notifier.uploadPattern(
              state.patternForSave,
              driveFileId,
              parentFolderId,
            );
          }
        }
      } else {
        await _saveAs(context);
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Save failed: $e');
    }
  }

  Future<void> _saveAs(BuildContext context) async {
    final state = ref.read(editorProvider);
    try {
      final path =
          await FileService.saveFileAs(state.patternForSave,
              compress: state.compressOnSave);
      if (path != null) {
        ref.read(editorProvider.notifier).setFilePath(path);
        ref.read(editorProvider.notifier).markSaved();
        if (context.mounted) showSuccess(context, 'Saved');
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Save failed: $e');
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
    ref.read(imageViewerProvider.notifier).set(null);
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
      final compress = ref.read(settingsProvider).compressNewFiles;
      try {
        await FileService.saveFile(pattern, filePath, compress: compress);
        ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
        ref.read(editorProvider.notifier).loadPattern(pattern, filePath: filePath, compressOnSave: compress);
        refreshFolder(ref, workspace);
      } catch (e) {
        if (context.mounted) showError(context, 'Could not create file: $e');
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
        final driveCompress = ref.read(settingsProvider).compressNewFiles;
        await FileService.saveFile(pattern, tempPath, compress: driveCompress);

        ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveParentFolderId: workspace.folderId,
          compressOnSave: driveCompress,
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
        if (context.mounted) showError(context, 'Could not create file: $e');
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
      showError(context, 'Could not upload file to Drive.');
    }
  }

  Future<void> _showExportDialog(
      BuildContext context, EditorState state) async {
    await showExportDialog(context, state.pattern);
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
            _InfoRow('Stitches',
                '${p.layers.fold(0, (sum, l) => sum + l.stitches.length)}'),
            if (state.filePath != null)
              _InfoRow(
                'File',
                state.driveParentFolderId != null
                    ? '${p.name}.stitchx  (Google Drive)'
                    : state.filePath!.split('/').last,
              ),
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

  Future<void> _scanPage(
      BuildContext context,
      String pdfPath,
      List<int> legendPageNumbers,
      List<int> gridPageNumbers,
      String title) async {
    _scanCancelled = false;
    final allPageNumbers = {
      ...legendPageNumbers,
      ...gridPageNumbers,
    }.toList()..sort();
    final renderMsg = allPageNumbers.length == 1
        ? 'Rendering page…'
        : 'Rendering ${allPageNumbers.length} pages…';
    _showScanOverlay(context, renderMsg);

    try {
      // Rasterise all unique pages in one batch.
      final allPages = await PdfScanner.rasterisePages(pdfPath, allPageNumbers);
      if (_scanCancelled) return;

      // Build page-number → bytes lookup.
      final pageByNumber = <int, Uint8List>{
        for (var i = 0; i < allPageNumbers.length; i++)
          allPageNumbers[i]: allPages[i],
      };

      final legendPages =
          legendPageNumbers.map((n) => pageByNumber[n]!).toList();
      final gridPages =
          gridPageNumbers.map((n) => pageByNumber[n]!).toList();

      final totalKb = allPages.fold(0, (s, p) => s + p.length) ~/ 1024;
      debugPrint('[PdfScanner] ${allPages.length} page(s) rendered: '
          '$totalKb KB total '
          '(legend: ${legendPages.length}, grid: ${gridPages.length})');

      // Auto-detect the grid layout on each page while the overlay is showing.
      _scanStatus.value = 'Detecting grid layout…';
      _scanSubtitle.value = null;
      final detections = await GridDetector.detectPages(gridPages);
      if (_scanCancelled) return;

      for (var i = 0; i < detections.length; i++) {
        final d = detections[i];
        if (d != null) {
          debugPrint('[GridDetector] page $i: '
              'cellW=${d.cellW.toStringAsFixed(1)} '
              'cellH=${d.cellH.toStringAsFixed(1)} '
              'conf=${d.confidence.toStringAsFixed(2)}');
        } else {
          debugPrint('[GridDetector] page $i: no result');
        }
      }

      // Present the grid-crop selection UI, pre-populated from detection.
      final initialCrops = detections
          .map((d) => d == null
              ? null
              : Rect.fromLTRB(
                  d.gridLeft, d.gridTop, d.gridRight, d.gridBottom))
          .toList();

      _removeScanOverlay();
      if (!context.mounted) return;
      final crops = await PatternScanCropScreen.show(
        context,
        pages: gridPages,
        initialCrops: initialCrops,
      );
      if (crops == null || !context.mounted) return;
      debugPrint('[PdfScanner] crop(s): ${crops.map((c) => c.cropRect).join(', ')}');

      // Step 2a — Prompt for pattern dimensions (cols × rows).
      _removeScanOverlay();
      if (!context.mounted) return;
      final size = await _promptPatternSize(context);
      if (size == null || !context.mounted) return;
      final (patternW, patternH) = size;

      // Step 2c — Build GridCellResult for each page directly from pattern dims.
      final pageCount = crops.length;
      final rowsPerPage = patternH ~/ pageCount;
      final extraRows   = patternH - rowsPerPage * pageCount;

      final cellResults = <GridCellResult>[];
      for (var i = 0; i < crops.length; i++) {
        final crop     = crops[i];
        final pageRows = rowsPerPage + (i == pageCount - 1 ? extraRows : 0);
        final cellW    = crop.cropRect.width  / patternW;
        final cellH    = crop.cropRect.height / pageRows;

        // Re-express the detected grid phase relative to this crop.
        // Clamp to 0 when the offset is > half a cell to avoid losing a column/row.
        final det = i < detections.length ? detections[i] : null;
        double phaseX = 0;
        double phaseY = 0;
        if (det != null) {
          final dx = det.gridLeft - crop.cropRect.left;
          final dy = det.gridTop  - crop.cropRect.top;
          phaseX = ((det.phaseX + dx) % cellW + cellW) % cellW;
          phaseY = ((det.phaseY + dy) % cellH + cellH) % cellH;
          if (phaseX > cellW * 0.5) phaseX = 0;
          if (phaseY > cellH * 0.5) phaseY = 0;
        }

        cellResults.add(GridCellResult(
          crop: crop,
          cellW: cellW,
          cellH: cellH,
          cellOffsetX: phaseX,
          cellOffsetY: phaseY,
          columns: ((crop.cropRect.width  - phaseX) / cellW).round().clamp(1, 9999),
          rows:    ((crop.cropRect.height - phaseY) / cellH).round().clamp(1, 9999),
        ));
      }
      debugPrint(
        '[PdfScanner] cell size(s): '
        '${cellResults.map((c) => '${c.columns}×${c.rows}').join(', ')}',
      );

      // Step 3 — Symbol sampling: user taps one cell per symbol type.
      final samples = await PatternScanSymbolScreen.show(
        context,
        cellResults: cellResults,
        legendPages: legendPages,
      );
      if (samples == null || !context.mounted) return;
      debugPrint('[PdfScanner] ${samples.length} symbol type(s) sampled');

      // Step 4 — Per-cell template matching.
      final matchResults = <GridMatchResult>[];
      for (int i = 0; i < cellResults.length; i++) {
        if (_scanCancelled) return;
        if (!context.mounted) return;
        final cellResult = cellResults[i];

        _showScanOverlay(context,
            'Scanning page ${i + 1} of ${cellResults.length}…');
        _scanSubtitle.value =
            '${cellResult.columns}×${cellResult.rows} cells';

        debugPrint('[CellScanner] page $i: '
            'cols=${cellResult.columns} rows=${cellResult.rows} '
            'cellW=${cellResult.cellW.toStringAsFixed(1)} '
            'cellH=${cellResult.cellH.toStringAsFixed(1)} '
            'offsetX=${cellResult.cellOffsetX.toStringAsFixed(1)} '
            'offsetY=${cellResult.cellOffsetY.toStringAsFixed(1)} '
            'samples=${samples.length}');

        final matchResult = await GridSymbolMatcher.matchGrid(
          gridResult: cellResult,
          samples: samples,
        );
        debugPrint(
            '[CellScanner] page $i: ${matchResult.cells.where((c) => !c.isEmpty).length} occupied, '
            '${matchResult.cells.where((c) => c.isEmpty).length} empty');
        matchResults.add(matchResult);
      }
      if (_scanCancelled) return;

      // Step 5 — Review / correct low-confidence cells.
      final totalLowConf =
          matchResults.fold<int>(0, (s, r) => s + r.lowConfidenceCount);
      var reviewedResults = matchResults;
      if (totalLowConf > 0) {
        _removeScanOverlay();
        if (!context.mounted) return;
        final reviewed = await PatternScanReviewScreen.show(
          context,
          matchResults: matchResults,
          cellResults: cellResults,
        );
        if (reviewed == null || !context.mounted) return;
        reviewedResults = reviewed;
      }

      final result = GridMatchResult.combineFromSamples(reviewedResults, samples);
      _removeScanOverlay();
      if (!context.mounted) return;

      if (reviewedResults.length == 1) {
        // ── Single grid: preview then load as a new full pattern ─────────────
        final pattern = await Navigator.of(context).push<CrossStitchPattern>(
          MaterialPageRoute(
            builder: (_) => PatternScanPreviewScreen(
              result: result,
              patternName: title,
            ),
          ),
        );
        if (pattern != null && context.mounted) {
          // Auto-save the new pattern next to the source PDF.
          final savePath =
              '${File(pdfPath).parent.path}${Platform.pathSeparator}$title.stitchx';
          final scanCompress = ref.read(settingsProvider).compressNewFiles;
          try {
            await FileService.saveFile(pattern, savePath, compress: scanCompress);
          } catch (_) {
            // Saving failed (e.g. read-only location) — load without a file path.
          }
          if (!context.mounted) return;
          ref.read(editorProvider.notifier).loadPattern(
            pattern,
            filePath: File(savePath).existsSync() ? savePath : null,
            compressOnSave: scanCompress,
          );
          ref.read(pdfViewerProvider.notifier).set(null);
    ref.read(imageViewerProvider.notifier).set(null);
        }
      } else {
        // ── Multiple grids: each page becomes a Snippet ──────────────────────
        // The user arranges them on the canvas via the Snippets panel.
        final notifier = ref.read(editorProvider.notifier);
        for (var i = 0; i < reviewedResults.length; i++) {
          notifier.addSnippet(
            reviewedResults[i].toSnippet('$title — page ${i + 1}'),
          );
        }
        if (context.mounted) {
          showSuccess(
            context,
            '${reviewedResults.length} grids added as snippets — '
            'open the Snippets panel to place them on the canvas.',
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e, st) {
      if (_scanCancelled) return;
      debugPrint('[PdfScanner] caught: $e\n$st');
      _removeScanOverlay();
      if (!context.mounted) return;
      _showScanError(context, e);
    } finally {
      _removeScanOverlay();
    }
  }

  /// Dialog shown when the AI did not detect pattern dimensions.
  /// Returns (cols, rows) or null if the user cancelled.
  Future<(int, int)?> _promptPatternSize(BuildContext context) async {
    final colsCtrl = TextEditingController();
    final rowsCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    final result = await showDialog<(int, int)>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter pattern size'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the pattern size in stitches. '
                'You can find this on the legend page of the PDF.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: colsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Enter a number';
                        return null;
                      },
                      autofocus: true,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('×', style: TextStyle(fontSize: 20)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: rowsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Enter a number';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop((
                  int.parse(colsCtrl.text),
                  int.parse(rowsCtrl.text),
                ));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  void _showScanError(BuildContext context, Object e) {
    debugPrint('[PdfScanner] error: $e');
    final msg = e.toString();
    final isRateLimit = msg.contains('Quota exceeded') ||
        msg.contains('quota') ||
        msg.contains('rate') ||
        msg.contains('RESOURCE_EXHAUSTED');

    if (isRateLimit) {
      // Try to extract the retry-after seconds from the message.
      final retryMatch =
          RegExp(r'retry in ([\d.]+)s', caseSensitive: false).firstMatch(msg);
      final retryStr = retryMatch != null
          ? ' Try again in ~${retryMatch.group(1)!.split('.').first}s.'
          : '';

      showWarning(context, 'Rate limit reached.$retryStr',
          duration: const Duration(seconds: 6));
    } else if (msg.contains('API key') || msg.contains('api_key') ||
        msg.contains('API_KEY_INVALID')) {
      showError(context, 'Invalid API key. Check your Gemini key in Settings.',
          duration: const Duration(seconds: 6));
    } else {
      showError(context, 'Scan failed: $msg',
          duration: const Duration(seconds: 6));
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final wsState = ref.watch(workspaceProvider);
    final driveState = ref.watch(googleDriveProvider);
    final isFileLoading = ref.watch(fileLoadingProvider);
    final openPdf = ref.watch(pdfViewerProvider);
    final openImage = ref.watch(imageViewerProvider);

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
        case LogicalKeyboardKey.digit8:
          notifier.setTool(DrawingTool.fill);
        case LogicalKeyboardKey.digit9:
          notifier.setDrawingMode(DrawingMode.erase);
          if (!editorState.fillEraseActive) notifier.toggleFillErase();
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
                icon: const Icon(Icons.document_scanner_outlined),
                tooltip: 'Scan page as pattern (Beta)',
                onPressed: () async {
                  final picked = await PdfPagePickerDialog.show(
                    context,
                    pdfPath: openPdf.localPath,
                    initialPage: _pdfPanelKey.currentState?.currentPage ?? 1,
                  );
                  if (picked != null && context.mounted) {
                    _scanPage(
                      context,
                      openPdf.localPath,
                      picked.legendPages,
                      picked.gridPages,
                      openPdf.title,
                    );
                  }
                },
              ),
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
                tooltip: editorState.blockMode ? 'Block mode: on' : 'Block mode: off',
                isSelected: editorState.blockMode,
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view),
                onPressed: () =>
                    ref.read(editorProvider.notifier).toggleBlockMode(),
                style: editorState.blockMode
                    ? IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
              PopupMenuButton<_MenuAction>(
                tooltip: 'More',
                onSelected: (action) {
                  switch (action) {
                    case _MenuAction.saveAs:
                      _saveAs(context);
                    case _MenuAction.export:
                      _showExportDialog(context, editorState);
                    case _MenuAction.resize:
                      _showResizeDialog(context, editorState);
                    case _MenuAction.patternInfo:
                      _showPatternInfo(context, editorState);
                    case _MenuAction.referenceImage:
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ReferenceImageSheet(),
                      );
                    case _MenuAction.toggleCompress:
                      ref.read(editorProvider.notifier).toggleCompressOnSave();
                    case _MenuAction.shortcuts:
                      showDialog(
                        context: context,
                        builder: (_) => const _ShortcutsDialog(),
                      );
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: _MenuAction.referenceImage,
                    child: _MenuRow(
                      icon: Icons.image_outlined,
                      label: 'Reference Image',
                      trailing: editorState.referenceImage != null &&
                              editorState.referenceVisible
                          ? Icon(Icons.check,
                              size: 16,
                              color: Theme.of(ctx).colorScheme.primary)
                          : null,
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.resize,
                    child: _MenuRow(
                        icon: Icons.aspect_ratio, label: 'Resize Aida'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.patternInfo,
                    child: _MenuRow(
                        icon: Icons.info_outline, label: 'Pattern Info'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _MenuAction.saveAs,
                    child: _MenuRow(
                        icon: Icons.save_as_outlined, label: 'Save As…'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.export,
                    child: _MenuRow(
                        icon: Icons.upload_outlined,
                        label: 'Export…'),
                  ),
                  if (editorState.isNativeFormat)
                    PopupMenuItem(
                      value: _MenuAction.toggleCompress,
                      child: _MenuRow(
                        icon: Icons.folder_zip_outlined,
                        label: editorState.compressOnSave
                            ? 'Compress file'
                            : 'Uncompress file',
                        trailing: editorState.compressOnSave
                            ? Icon(Icons.check,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                    ),
                  if (defaultTargetPlatform != TargetPlatform.iOS &&
                      defaultTargetPlatform != TargetPlatform.android)
                    const PopupMenuItem(
                      value: _MenuAction.shortcuts,
                      child: _MenuRow(
                          icon: Icons.keyboard_outlined,
                          label: 'Keyboard Shortcuts'),
                    ),
                ],
              ),
            ],
            // Stitch mode actions — Demo + Screen Lock
            if (editorState.isFileOpen && editorState.stitchMode && openPdf == null) ...[
              StitchDemoButton(state: editorState),
              _WorkspaceScreenLockButton(),
              const SizedBox(width: 4),
            ],
          ],
        ),
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar + draggable resize handle
                if (wsState.sidebarVisible) ...[
                  SizedBox(width: wsState.sidebarWidth, child: const FileSidebar()),
                  _ResizeDivider(
                    onDrag: (delta) => ref
                        .read(workspaceProvider.notifier)
                        .setSidebarWidth(wsState.sidebarWidth + delta),
                  ),
                ],
                // Editor, PDF viewer, image viewer, or empty state
                Expanded(
                  child: openPdf != null
                      ? Focus(
                          autofocus: true,
                          onKeyEvent: handleKeys,
                          child: PdfViewerPanel(key: _pdfPanelKey, path: openPdf.localPath),
                        )
                      : openImage != null
                          ? Focus(
                              autofocus: true,
                              onKeyEvent: handleKeys,
                              child: ImageViewerPanel(path: openImage.localPath),
                            )
                          : editorState.isFileOpen
                              ? Focus(
                                  autofocus: true,
                                  onKeyEvent: handleKeys,
                                  child: Stack(
                                    children: [
                                      Column(
                                        children: [
                                          if (!editorState.isNativeFormat)
                                            _ImportBanner(
                                              filePath: editorState.filePath!,
                                              onSaveAs: () => _saveAs(context),
                                            ),
                                          const Expanded(child: PatternCanvas()),
                                          const SafeArea(
                                            top: false,
                                            child: EditorToolbar(),
                                          ),
                                        ],
                                      ),
                                      // FAB anchored to canvas column so it
                                      // never overlaps the left file sidebar.
                                      Positioned(
                                        left: 12,
                                        bottom: editorState.stitchMode ? 16 : 64,
                                        child: FloatingActionButton.extended(
                                          onPressed: () => ref
                                              .read(editorProvider.notifier)
                                              .toggleStitchMode(),
                                          icon: Icon(editorState.stitchMode
                                              ? Icons.edit_outlined
                                              : Icons.auto_stories_outlined),
                                          label: Text(editorState.stitchMode
                                              ? 'Exit Stitch Mode'
                                              : 'Stitch Mode'),
                                          backgroundColor: editorState.stitchMode
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                              : null,
                                          foregroundColor: editorState.stitchMode
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSecondaryContainer
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _EmptyState(
                                  workspace: wsState.workspace,
                                  onNewFile: () => _newFileInWorkspace(
                                      context, wsState.workspace),
                                ),
                ),
                const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
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
      ),
    );
  }
}

