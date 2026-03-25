import 'dart:io';
import 'package:flutter/material.dart';

/// Inline image viewer that fills the canvas area.
/// Supports pinch-to-zoom, scroll-to-zoom, and pan.
class ImageViewerPanel extends StatelessWidget {
  final String path;

  const ImageViewerPanel({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.1,
      maxScale: 10.0,
      child: Center(
        child: Image.file(
          File(path),
          errorBuilder: (context, error, stack) => const Center(
            child: Text('Could not load image'),
          ),
        ),
      ),
    );
  }
}
