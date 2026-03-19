import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A pan-and-zoomable read-only PDF viewer.
///
/// Ctrl + scroll wheel zooms (handled natively by pdfrx).
/// Trackpad two-finger swipe pans, pinch zooms.
/// Use [PdfViewerPanelState.zoomIn] / [zoomOut] for programmatic zoom
/// (toolbar buttons, keyboard shortcuts).
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

  void zoomIn() {
    if (_controller.isReady) _controller.zoomUp();
  }

  void zoomOut() {
    if (_controller.isReady) _controller.zoomDown();
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
