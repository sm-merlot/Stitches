import 'package:flutter/material.dart' show Colors, Rect;
import 'package:flutter/widgets.dart' show Offset;
import 'package:stitches/models/layer/layer.dart';
import 'package:stitches/models/layer/layer_item.dart';
import 'package:stitches/models/page/page_config.dart';
import 'package:stitches/models/page/page_layout.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/widgets/canvas/canvas_viewport.dart';

// ─── Shared viewport + pattern dimensions ────────────────────────────────────

const cellSize = 20.0;
const vp = CanvasViewport(cellSize: cellSize, panOffset: Offset.zero, scale: 1.0);
const patW = 50;
const patH = 50;

// ─── Fixed test layer ID ──────────────────────────────────────────────────────

const kLayerId = 'layer1';

// ─── Pattern / layer builders ─────────────────────────────────────────────────

Layer fakeLayer({
  String id = kLayerId,
  List<Stitch> stitches = const [],
  bool visible = true,
  double opacity = 1.0,
}) =>
    Layer(
      id: id,
      name: 'Layer 1',
      visible: visible,
      opacity: opacity,
      stitches: stitches,
    );

CrossStitchPattern fakePattern({
  int width = 20,
  int height = 20,
  List<Layer>? layers,
}) {
  final ls = layers ?? [fakeLayer()];
  return CrossStitchPattern(
    name: 'test',
    width: width,
    height: height,
    aidaColor: Colors.white,
    threads: const {},
    layerItems: ls.map((l) => LayerLeaf(layer: l)).toList(),
  );
}

// ─── EditorState builders ─────────────────────────────────────────────────────

EditorState fakeEditState({
  CrossStitchPattern? pattern,
  DrawingMode drawingMode = DrawingMode.draw,
  DrawingTool currentTool = DrawingTool.fullStitch,
  PartialSubTool partialSubTool = PartialSubTool.diagonalForward,
  String? selectedThreadId = 'DMC310',
  bool fillEraseActive = false,
  int eraserSize = 1,
  bool backstitchChainMode = false,
  Offset? backstitchStartPoint,
}) =>
    EditorState(
      pattern: pattern ?? fakePattern(),
      mode: AppMode.edit,
      selectedThreadId: selectedThreadId,
      activeLayerId: kLayerId,
      editSession: EditSessionState(
        drawingMode: drawingMode,
        currentTool: currentTool,
        partialSubTool: partialSubTool,
        fillEraseActive: fillEraseActive,
        eraserSize: eraserSize,
        backstitchChainMode: backstitchChainMode,
        backstitchStartPoint: backstitchStartPoint,
      ),
    );

EditorState fakeViewState({
  CrossStitchPattern? pattern,
}) =>
    EditorState(
      pattern: pattern ?? fakePattern(),
      mode: AppMode.view,
      activeLayerId: kLayerId,
      editSession: const EditSessionState(drawingMode: DrawingMode.pan),
    );

EditorState fakeStitchState({
  CrossStitchPattern? pattern,
  bool stitchCrossMode = false,
  String? stitchFocusThreadId,
  bool hasSelection = false,
  bool pagesEnabled = false,
}) {
  final pat = pattern ?? fakePattern();
  PageLayout? pageLayout;
  CrossStitchPattern finalPat = pat;
  if (pagesEnabled) {
    const config = PageConfig(
      enabled: true,
      pageWidth: 10,
      pageHeight: 10,
      tolerance: 0,
    );
    finalPat = pat.copyWith(pageConfig: config);
    pageLayout = PageLayout.compute(config, finalPat);
  }
  return EditorState(
    pattern: finalPat,
    mode: AppMode.stitch,
    activeLayerId: kLayerId,
    editSession: EditSessionState(
      drawingMode: DrawingMode.select,
      selectionRect: hasSelection ? const Rect.fromLTWH(0, 0, 2, 2) : null,
    ),
    stitchSession: StitchSessionState(
      crossMode: stitchCrossMode,
      focusThreadId: stitchFocusThreadId,
      pageLayout: pageLayout,
    ),
  );
}
