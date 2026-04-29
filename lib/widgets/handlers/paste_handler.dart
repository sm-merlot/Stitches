import 'package:flutter/widgets.dart' show Offset;
import '../../models/pattern.dart';
import '../../models/stitch/stitch.dart';
import '../../models/stitch/stitch_geometry.dart';
import '../canvas/canvas_viewport.dart';

/// Handles paste-mode ghost positioning, Shift edge-snapping, and commit.
///
/// Owns paste-origin state, ghost-stitch cache, and Ctrl/Shift modifier-key
/// state.  [AidaWidget] forwards events; after each call it reads
/// [pasteOrigin], [ctrlHeld], [shiftHeld], and [buildGhostStitches] to drive
/// the overlay painter and cursor.
///
/// Writes back via injected callbacks — no direct [EditorNotifier] access,
/// so this handler is unit-testable without Riverpod.
class PasteHandler {
  Offset? _pasteOrigin;
  bool _ctrlHeld = false;
  bool _shiftHeld = false;

  // Ghost-stitch cache — avoids re-allocating the offset list on every build.
  List<Stitch>? _cachedGhostStitches;
  (int, int)? _lastGhostDxDy;
  List<Stitch>? _lastGhostClipboard;

  final void Function(int dx, int dy) onCommitPaste;
  final void Function() onCancelSelection;
  final void Function() scheduleRebuild;

  PasteHandler({
    required this.onCommitPaste,
    required this.onCancelSelection,
    required this.scheduleRebuild,
  });

  // ── Getters ──────────────────────────────────────────────────────────────────

  Offset? get pasteOrigin => _pasteOrigin;
  bool get ctrlHeld => _ctrlHeld;
  bool get shiftHeld => _shiftHeld;

  // ── Modifier key tracking ─────────────────────────────────────────────────────

  /// Update Ctrl/Shift state from [HardwareKeyboard].  Schedules a rebuild only
  /// when modifier state actually changes (avoids spurious repaints).
  void updateModifiers({required bool ctrl, required bool shift}) {
    if (ctrl == _ctrlHeld && shift == _shiftHeld) return;
    _ctrlHeld = ctrl;
    _shiftHeld = shift;
    scheduleRebuild();
  }

  // ── Paste offset computation ──────────────────────────────────────────────────

  /// Returns the (dx, dy) offset that centres [clips] on [cursorCell].
  (int, int) centeredOffset(Offset cursorCell, List<Stitch> clips) {
    if (clips.isEmpty) return (cursorCell.dx.toInt(), cursorCell.dy.toInt());
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in clips) {
      final b = s.bounds;
      if (b.minX < minX) minX = b.minX;
      if (b.maxX > maxX) maxX = b.maxX;
      if (b.minY < minY) minY = b.minY;
      if (b.maxY > maxY) maxY = b.maxY;
    }
    return (
      (cursorCell.dx + 0.5 - (minX + maxX) / 2).round(),
      (cursorCell.dy + 0.5 - (minY + maxY) / 2).round(),
    );
  }

  /// Returns the (dx, dy) offset for [clips] at [cursorCell], snapping
  /// clipboard edges to canvas boundaries and same-colour stitches when
  /// [shiftHeld] is true.
  ///
  /// Canvas-edge snapping triggers when the clipboard edge would land within
  /// [_edgeThreshold] cells of the canvas boundary (left, right, top, bottom,
  /// or centre on each axis).  Stitch snapping then runs on any unsnapped axis.
  (int, int) effectiveOffset(
    Offset cursorCell,
    List<Stitch> clips,
    CrossStitchPattern pattern,
  ) {
    final (cx, cy) = centeredOffset(cursorCell, clips);
    if (!_shiftHeld || clips.isEmpty) return (cx, cy);

    var clipMinX = double.infinity, clipMaxX = double.negativeInfinity;
    var clipMinY = double.infinity, clipMaxY = double.negativeInfinity;
    for (final s in clips) {
      final b = s.bounds;
      if (b.minX < clipMinX) clipMinX = b.minX;
      if (b.maxX > clipMaxX) clipMaxX = b.maxX;
      if (b.minY < clipMinY) clipMinY = b.minY;
      if (b.maxY > clipMaxY) clipMaxY = b.maxY;
    }

    final w = pattern.width.toDouble();
    final h = pattern.height.toDouble();
    const edgeThreshold = 3.0;
    final cxd = cx.toDouble(), cyd = cy.toDouble();

    final leftDist    = (clipMinX + cxd).abs();
    final rightDist   = (w - clipMaxX - cxd).abs();
    final topDist     = (clipMinY + cyd).abs();
    final bottomDist  = (h - clipMaxY - cyd).abs();
    final centreXDist = ((clipMinX + clipMaxX) / 2 + cxd - w / 2).abs();
    final centreYDist = ((clipMinY + clipMaxY) / 2 + cyd - h / 2).abs();

    double? snapDx, snapDy;
    if (leftDist <= edgeThreshold && leftDist <= rightDist) {
      snapDx = -clipMinX;                               // clipboard left → canvas left
    } else if (rightDist <= edgeThreshold) {
      snapDx = w - clipMaxX;                            // clipboard right → canvas right
    } else if (centreXDist <= edgeThreshold) {
      snapDx = w / 2 - (clipMinX + clipMaxX) / 2;      // clipboard centre → canvas centre
    }
    if (topDist <= edgeThreshold && topDist <= bottomDist) {
      snapDy = -clipMinY;                               // clipboard top → canvas top
    } else if (bottomDist <= edgeThreshold) {
      snapDy = h - clipMaxY;                            // clipboard bottom → canvas bottom
    } else if (centreYDist <= edgeThreshold) {
      snapDy = h / 2 - (clipMinY + clipMaxY) / 2;      // clipboard centre → canvas centre
    }

    // Same-colour stitch snapping: butt clipboard edge flush against the nearest
    // canvas stitch sharing a thread colour.  Only runs on axes not already
    // snapped to a canvas edge.
    const stitchThreshold = 3.0;
    final clipThreadIds = clips.map((s) => s.threadId).toSet();
    if (snapDx == null || snapDy == null) {
      final xCandidates = <double>[];
      final yCandidates = <double>[];
      for (final cs in pattern.stitches) {
        if (!clipThreadIds.contains(cs.threadId)) continue;
        final b = cs.bounds;
        if (snapDx == null) {
          xCandidates.add(b.maxX - clipMinX); // clipboard left butts stitch right
          xCandidates.add(b.minX - clipMaxX); // clipboard right butts stitch left
        }
        if (snapDy == null) {
          yCandidates.add(b.maxY - clipMinY); // clipboard top butts stitch bottom
          yCandidates.add(b.minY - clipMaxY); // clipboard bottom butts stitch top
        }
      }
      double? pickNearest(List<double> candidates, double current) {
        double? best;
        double bestDist = stitchThreshold;
        for (final c in candidates) {
          final d = (c - current).abs();
          if (d <= bestDist) {
            bestDist = d;
            best = c;
          }
        }
        return best;
      }
      snapDx ??= pickNearest(xCandidates, cx.toDouble());
      snapDy ??= pickNearest(yCandidates, cy.toDouble());
    }

    return (
      (snapDx ?? cx.toDouble()).round(),
      (snapDy ?? cy.toDouble()).round(),
    );
  }

  // ── Ghost stitch cache ────────────────────────────────────────────────────────

  /// Returns the offset clipboard stitches for the paste preview.
  ///
  /// Reuses the cached list when [dx], [dy], and [clipboard] identity are all
  /// unchanged — avoids a List allocation on every build during ghost preview.
  List<Stitch> buildGhostStitches(
    int dx,
    int dy,
    List<Stitch> clipboard,
    Stitch Function(Stitch, int, int) offsetStitch,
  ) {
    if (_lastGhostDxDy == (dx, dy) &&
        identical(_lastGhostClipboard, clipboard)) {
      return _cachedGhostStitches!;
    }
    _lastGhostDxDy = (dx, dy);
    _lastGhostClipboard = clipboard;
    return _cachedGhostStitches =
        clipboard.map((s) => offsetStitch(s, dx, dy)).toList();
  }

  // ── Origin management ─────────────────────────────────────────────────────────

  /// Updates the paste origin from a screen position.  No-op if the cell did
  /// not change (avoids unnecessary repaints during hover).
  void updateOrigin(Offset screenPos, CanvasViewport viewport) {
    final c = viewport.screenToCanvas(screenPos);
    final (cx, cy) = viewport.canvasToCell(c);
    final newOrigin = Offset(cx.toDouble(), cy.toDouble());
    if (newOrigin == _pasteOrigin) return;
    _pasteOrigin = newOrigin;
    scheduleRebuild();
  }

  /// Sets the paste origin from a screen position without deduplicating.
  /// Used in pencil-confirm mode where the pointer-down always repositions.
  void setOrigin(Offset screenPos, CanvasViewport viewport) {
    final c = viewport.screenToCanvas(screenPos);
    final (cx, cy) = viewport.canvasToCell(c);
    _pasteOrigin = Offset(cx.toDouble(), cy.toDouble());
  }

  void clearOrigin() {
    _pasteOrigin = null;
    scheduleRebuild();
  }

  // ── Commit ────────────────────────────────────────────────────────────────────

  /// Commits the paste at the current origin, applying edge snap if Shift is
  /// held.  Returns `true` if a paste was committed, `false` if origin or
  /// clipboard is missing.
  bool commit(CrossStitchPattern pattern, List<Stitch>? clipboard) {
    final origin = _pasteOrigin;
    if (origin == null || clipboard == null) return false;
    final (dx, dy) = effectiveOffset(origin, clipboard, pattern);
    onCommitPaste(dx, dy);
    if (!_ctrlHeld) onCancelSelection();
    return true;
  }
}
