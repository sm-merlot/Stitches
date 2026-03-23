import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Result of the two-step page-picker dialog.
class PagePickerResult {
  /// 1-based page numbers containing the colour legend / key.
  final List<int> legendPages;

  /// 1-based page numbers containing the stitch grid(s) to scan.
  final List<int> gridPages;

  const PagePickerResult({
    required this.legendPages,
    required this.gridPages,
  });
}

/// Two-step dialog for selecting PDF pages to scan.
///
/// Step 1 — Select the page(s) containing the colour legend / key.
/// Step 2 — Select the page(s) containing the stitch grid(s).
///
/// Returns a [PagePickerResult], or null if cancelled.
class PdfPagePickerDialog extends StatefulWidget {
  final String pdfPath;
  final int initialPage; // pre-selected page (1-based)

  const PdfPagePickerDialog({
    super.key,
    required this.pdfPath,
    required this.initialPage,
  });

  static Future<PagePickerResult?> show(
    BuildContext context, {
    required String pdfPath,
    required int initialPage,
  }) {
    return showDialog<PagePickerResult>(
      context: context,
      builder: (_) => PdfPagePickerDialog(
        pdfPath: pdfPath,
        initialPage: initialPage,
      ),
    );
  }

  @override
  State<PdfPagePickerDialog> createState() => _PdfPagePickerDialogState();
}

enum _Step { legend, grid }

class _PdfPagePickerDialogState extends State<PdfPagePickerDialog> {
  PdfDocument? _doc;
  int _totalPages = 0;
  String? _error;
  _Step _step = _Step.legend;

  late final Set<int> _legendSelected; // 1-based
  late final Set<int> _gridSelected;   // 1-based

  @override
  void initState() {
    super.initState();
    _legendSelected = {};
    _gridSelected = {};
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await PdfDocument.openFile(widget.pdfPath);
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _doc = doc;
        _totalPages = doc.pages.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  Set<int> get _active =>
      _step == _Step.legend ? _legendSelected : _gridSelected;

  void _toggle(int pageNumber) {
    setState(() {
      if (_active.contains(pageNumber)) {
        _active.remove(pageNumber);
      } else {
        _active.add(pageNumber);
      }
    });
  }

  void _next() => setState(() => _step = _Step.grid);

  void _confirm() {
    Navigator.of(context).pop(PagePickerResult(
      legendPages: _legendSelected.toList()..sort(),
      gridPages: _gridSelected.toList()..sort(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLegendStep = _step == _Step.legend;
    final n = _active.length;

    final stepLabel = isLegendStep
        ? 'Step 1 of 2 — Colour legend pages'
        : 'Step 2 of 2 — Stitch grid pages';
    final stepHint = isLegendStep
        ? 'Select the page(s) that contain the colour key / legend table.'
        : 'Select the page(s) that contain the stitch grid(s) to scan.';
    final actionLabel = isLegendStep
        ? 'Next'
        : (n == 1 ? 'Scan 1 page' : 'Scan $n pages');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stepLabel, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          stepHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),

            // Step indicator pills
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _StepPill(
                    number: 1,
                    label: 'Legend',
                    active: isLegendStep,
                    done: !isLegendStep,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isLegendStep
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StepPill(
                    number: 2,
                    label: 'Grid',
                    active: !isLegendStep,
                    done: false,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Beta callout
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.science_outlined,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Beta feature — results may be inaccurate. '
                          'Always review the preview before importing.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Grid
            Flexible(child: _buildGrid(context)),

            // Footer
            const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (!isLegendStep)
                    TextButton.icon(
                      onPressed: () => setState(() => _step = _Step.legend),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _active.isEmpty
                        ? null
                        : (isLegendStep ? _next : _confirm),
                    icon: Icon(
                      isLegendStep
                          ? Icons.arrow_forward
                          : Icons.document_scanner_outlined,
                      size: 18,
                    ),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not open PDF: $_error',
            style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }

    if (_doc == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _totalPages,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final isSelected = _active.contains(pageNumber);
        final selectionIndex = isSelected
            ? (_active.toList()..sort()).indexOf(pageNumber) + 1
            : null;
        // On the grid step, also mark pages already chosen as legend pages.
        final isLegendPage = _step == _Step.grid &&
            _legendSelected.contains(pageNumber);
        return _PageThumbnail(
          doc: _doc!,
          pageIndex: index,
          pageNumber: pageNumber,
          isSelected: isSelected,
          selectionIndex: selectionIndex,
          legendBadge: isLegendPage && !isSelected,
          onTap: () => _toggle(pageNumber),
        );
      },
    );
  }
}

// ── Step pill ─────────────────────────────────────────────────────────────────

class _StepPill extends StatelessWidget {
  final int number;
  final String label;
  final bool active;
  final bool done;

  const _StepPill({
    required this.number,
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = (active || done)
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (active || done) ? color : null,
            border: !(active || done) ? Border.all(color: color, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: done
              ? Icon(Icons.check, size: 13, color: theme.colorScheme.onPrimary)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: (active || done)
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ── Single thumbnail ──────────────────────────────────────────────────────────

class _PageThumbnail extends StatefulWidget {
  final PdfDocument doc;
  final int pageIndex;
  final int pageNumber;
  final bool isSelected;
  final int? selectionIndex; // 1-based order badge, null if not selected
  final bool legendBadge;    // show 'L' badge (grid step, page already in legend)
  final VoidCallback onTap;

  const _PageThumbnail({
    required this.doc,
    required this.pageIndex,
    required this.pageNumber,
    required this.isSelected,
    required this.selectionIndex,
    required this.legendBadge,
    required this.onTap,
  });

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  Future<ui.Image?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _render();
  }

  Future<ui.Image?> _render() async {
    final page = widget.doc.pages[widget.pageIndex];
    final scale = 120.0 / page.width;
    final pdfImage = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: 0xffffffff,
    );
    if (pdfImage == null) return null;
    final image = await pdfImage.createImage();
    pdfImage.dispose();
    return image;
  }

  @override
  void dispose() {
    _future?.then((img) => img?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: widget.isSelected ? 2.5 : 1,
          ),
          color: widget.isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
              : null,
        ),
        child: Stack(
          children: [
            // Page image + label
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5)),
                    child: FutureBuilder<ui.Image?>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.hasData && snap.data != null) {
                          return RawImage(
                            image: snap.data!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                          );
                        }
                        if (snap.hasError) {
                          return const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  size: 24));
                        }
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    'Page ${widget.pageNumber}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: widget.isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: widget.isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            // Selection order badge (top-right)
            if (widget.selectionIndex != null)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.selectionIndex}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // Legend badge (top-left) — shown on grid step for previously
            // chosen legend pages
            if (widget.legendBadge)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'L',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
