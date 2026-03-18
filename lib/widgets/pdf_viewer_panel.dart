import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A pan-and-zoomable read-only PDF viewer.
/// Wraps [PdfViewer.file] from the pdfrx package, which provides built-in
/// pinch-to-zoom, scroll-wheel zoom, and drag-to-pan on all platforms.
class PdfViewerPanel extends StatefulWidget {
  final String path;

  const PdfViewerPanel({super.key, required this.path});

  @override
  State<PdfViewerPanel> createState() => _PdfViewerPanelState();
}

class _PdfViewerPanelState extends State<PdfViewerPanel> {
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      widget.path,
      params: PdfViewerParams(
        margin: 8,
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
