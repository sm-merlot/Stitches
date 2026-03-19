import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A pan-and-zoomable read-only PDF viewer.
///
/// On macOS, mouse scroll wheel behaviour is overridden:
///   • Vertical scroll → pans the document
///   • Ctrl + vertical scroll → zooms the document
///
/// Trackpad is left to pdfrx's native handling (two-finger swipe pans,
/// pinch zooms). Use [PdfViewerPanelState.zoomIn] / [zoomOut] for
/// programmatic zoom (toolbar buttons, keyboard shortcuts).
class PdfViewerPanel extends StatefulWidget {
  final String path;

  const PdfViewerPanel({super.key, required this.path});

  @override
  PdfViewerPanelState createState() => PdfViewerPanelState();
}

class PdfViewerPanelState extends State<PdfViewerPanel> {
  final _controller = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;

  // Deduplication: pointerRouter.route fires once per hit-test entry in the
  // dispatch path — we only want to act once per physical scroll event.
  Duration _lastScrollTimestamp = Duration.zero;

  void zoomIn() {
    if (_controller.isReady) _controller.zoomUp();
  }

  void zoomOut() {
    if (_controller.isReady) _controller.zoomDown();
  }

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalScroll);
    }
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.pointerRouter.removeGlobalRoute(_handleGlobalScroll);
    }
    super.dispose();
  }

  /// Intercepts Ctrl + vertical mouse scroll on macOS and converts it to zoom.
  /// Plain vertical scroll is left for pdfrx to handle as a pan.
  void _handleGlobalScroll(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return; // trackpad handled natively
    if (!_controller.isReady) return;

    final dy = event.scrollDelta.dy;
    if (dy.abs() < 1.0) return;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrlHeld = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (!ctrlHeld) return; // plain scroll: let pdfrx pan normally

    // Deduplicate: global route may fire more than once per physical event.
    if (event.timeStamp == _lastScrollTimestamp) return;
    _lastScrollTimestamp = event.timeStamp;

    // Bounds check: ignore scrolls outside this widget.
    final renderBox = _controller.renderBox;
    if (renderBox == null || !renderBox.attached) return;
    final localPos = renderBox.globalToLocal(event.position);
    if (!(Offset.zero & renderBox.size).contains(localPos)) return;

    // ── Ctrl + vertical scroll → zoom ─────────────────────────────────────
    // Microtask fires after pdfrx's pan update but before the next frame,
    // so setZoom is the last write to _txController and wins at render time.
    final targetZoom = (_controller.currentZoom * math.exp(-dy / 200.0))
        .clamp(_controller.minScale, 8.0);
    Future.microtask(() {
      if (!mounted || !_controller.isReady) return;
      _controller.setZoom(localPos, targetZoom, duration: Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      widget.path,
      controller: _controller,
      params: PdfViewerParams(
        margin: 8,
        scrollByMouseWheel: 0.5,
        onDocumentChanged: (doc) {
          if (doc != null) {
            setState(() => _totalPages = doc.pages.length);
          } else {
            setState(() => _totalPages = 0);
          }
        },
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            setState(() => _currentPage = pageNumber);
          }
        },
        viewerOverlayBuilder: (context, size, handleLinkTap) {
          if (_totalPages <= 1) return const [];
          return [
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_currentPage / $_totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ];
        },
      ),
    );
  }
}
