part of 'editor_provider.dart';

// ─── EditSessionState ─────────────────────────────────────────────────────────

/// Session state for edit mode (tool, drawing mode, clipboard, reference image,
/// selection, eraser, etc.).
class EditSessionState {
  final DrawingTool currentTool;
  final DrawingMode drawingMode;
  final Offset? backstitchStartPoint;

  /// When true, backstitch drawing chains: the end point of one backstitch
  /// becomes the start point of the next. Toggled via toolbar (touch) or
  /// held via Ctrl (desktop).
  final bool backstitchChainMode;
  final Rect? selectionRect;
  final List<Stitch>? clipboard;
  final List<Thread>? clipboardThreads;
  final bool clipboardFromSnippet;

  /// Edge length of the eraser square (1 = single cell, 2 = 2×2, etc.).
  final int eraserSize;

  /// When true, erase mode uses flood-fill erase instead of the square eraser.
  final bool fillEraseActive;

  /// When true, selection operations act on all visible layers instead of just
  /// the active layer.
  final bool canvasSelectionMode;

  /// Non-null when the notifier wants AidaWidget to show a one-shot warning
  /// banner. AidaWidget clears this immediately after showing it.
  final String? pendingCanvasWarning;

  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool referenceVisible;
  final bool colourMode;

  const EditSessionState({
    this.currentTool = DrawingTool.fullStitch,
    this.drawingMode = DrawingMode.draw,
    this.backstitchStartPoint,
    this.backstitchChainMode = false,
    this.selectionRect,
    this.clipboard,
    this.clipboardThreads,
    this.clipboardFromSnippet = false,
    this.eraserSize = 1,
    this.fillEraseActive = false,
    this.canvasSelectionMode = false,
    this.pendingCanvasWarning,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.referenceVisible = true,
    this.colourMode = false,
  });

  static const _sentinel = Object();

  EditSessionState copyWith({
    DrawingTool? currentTool,
    DrawingMode? drawingMode,
    Object? backstitchStartPoint = _sentinel,
    bool? backstitchChainMode,
    Object? selectionRect = _sentinel,
    Object? clipboard = _sentinel,
    Object? clipboardThreads = _sentinel,
    bool? clipboardFromSnippet,
    int? eraserSize,
    bool? fillEraseActive,
    bool? canvasSelectionMode,
    Object? pendingCanvasWarning = _sentinel,
    Object? referenceImage = _sentinel,
    double? referenceOpacity,
    bool? referenceVisible,
    bool? colourMode,
  }) =>
      EditSessionState(
        currentTool: currentTool ?? this.currentTool,
        drawingMode: drawingMode ?? this.drawingMode,
        backstitchStartPoint: backstitchStartPoint == _sentinel
            ? this.backstitchStartPoint
            : backstitchStartPoint as Offset?,
        backstitchChainMode: backstitchChainMode ?? this.backstitchChainMode,
        selectionRect: selectionRect == _sentinel
            ? this.selectionRect
            : selectionRect as Rect?,
        clipboard:
            clipboard == _sentinel ? this.clipboard : clipboard as List<Stitch>?,
        clipboardThreads: clipboardThreads == _sentinel
            ? this.clipboardThreads
            : clipboardThreads as List<Thread>?,
        clipboardFromSnippet: clipboardFromSnippet ?? this.clipboardFromSnippet,
        eraserSize: eraserSize ?? this.eraserSize,
        fillEraseActive: fillEraseActive ?? this.fillEraseActive,
        canvasSelectionMode: canvasSelectionMode ?? this.canvasSelectionMode,
        pendingCanvasWarning: pendingCanvasWarning == _sentinel
            ? this.pendingCanvasWarning
            : pendingCanvasWarning as String?,
        referenceImage: referenceImage == _sentinel
            ? this.referenceImage
            : referenceImage as ui.Image?,
        referenceOpacity: referenceOpacity ?? this.referenceOpacity,
        referenceVisible: referenceVisible ?? this.referenceVisible,
        colourMode: colourMode ?? this.colourMode,
      );
}
