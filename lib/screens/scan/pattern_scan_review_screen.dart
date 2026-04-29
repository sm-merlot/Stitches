import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'pattern_scan_cell_screen.dart';
import '../../services/scan/scan_result.dart';
import '../../services/scan/grid_symbol_matcher.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

/// One low-confidence cell awaiting user review.
class _Flagged {
  final int pageIdx;
  final CellMatch cell;

  _Flagged(this.pageIdx, this.cell);

  String get key => '${pageIdx}_${cell.col}_${cell.row}';
}

// ─── Thumbnail batch extraction (background isolate) ─────────────────────────

class _ThumbBatchParams {
  final List<Uint8List> pages;
  final List<_ThumbReq> requests;

  const _ThumbBatchParams({
    required this.pages,
    required this.requests,
  });
}

class _ThumbReq {
  final String key;
  final int pageIdx;
  final double cropLeft;
  final double cropTop;
  final double cellW;
  final double cellH;
  final int col;
  final int row;

  const _ThumbReq({
    required this.key,
    required this.pageIdx,
    required this.cropLeft,
    required this.cropTop,
    required this.cellW,
    required this.cellH,
    required this.col,
    required this.row,
  });
}

// Top-level function required by compute().
Map<String, Uint8List> _extractThumbs(_ThumbBatchParams p) {
  final result = <String, Uint8List>{};
  // Decode each page once and reuse across all of its cells.
  final decoded = <int, img.Image?>{};

  for (final req in p.requests) {
    decoded.putIfAbsent(req.pageIdx, () => img.decodePng(p.pages[req.pageIdx]));
    final page = decoded[req.pageIdx];
    if (page == null) continue;

    final px = (req.cropLeft + req.col * req.cellW).round().clamp(0, page.width - 1);
    final py = (req.cropTop + req.row * req.cellH).round().clamp(0, page.height - 1);
    final pw = req.cellW.round().clamp(1, page.width - px);
    final ph = req.cellH.round().clamp(1, page.height - py);

    var crop = img.copyCrop(page, x: px, y: py, width: pw, height: ph);
    crop = img.copyResize(
      crop,
      width: 80,
      height: 80,
      interpolation: img.Interpolation.average,
    );
    result[req.key] = Uint8List.fromList(img.encodePng(crop));
  }
  return result;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Full-screen review UI for low-confidence pixel-matched cells.
///
/// Shows each flagged cell as a thumbnail card. Tapping a card opens a symbol
/// picker so the user can reassign it (or mark it as empty background).
///
/// Pops with a [List<GridMatchResult>] (with corrections applied) when
/// confirmed, or null if the user cancels.
class PatternScanReviewScreen extends StatefulWidget {
  final List<GridMatchResult> matchResults;
  final List<GridCellResult> cellResults;

  const PatternScanReviewScreen({
    super.key,
    required this.matchResults,
    required this.cellResults,
  });

  static Future<List<GridMatchResult>?> show(
    BuildContext context, {
    required List<GridMatchResult> matchResults,
    required List<GridCellResult> cellResults,
  }) =>
      Navigator.of(context).push<List<GridMatchResult>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PatternScanReviewScreen(
            matchResults: matchResults,
            cellResults: cellResults,
          ),
        ),
      );

  @override
  State<PatternScanReviewScreen> createState() =>
      _PatternScanReviewScreenState();
}

class _PatternScanReviewScreenState extends State<PatternScanReviewScreen> {
  late final List<_Flagged> _flagged;

  /// Override map. Key = `"pi_col_row"`.
  /// - Absent: not yet reviewed.
  /// - Empty string value: user marked as empty/background.
  /// - Non-empty string value: user-assigned DMC code.
  final Map<String, String> _overrides = {};

  final Map<String, Uint8List> _thumbs = {};
  bool _loadingThumbs = true;

  @override
  void initState() {
    super.initState();
    _flagged = [
      for (var pi = 0; pi < widget.matchResults.length; pi++)
        for (final cell in widget.matchResults[pi].cells)
          if (cell.isLowConfidence) _Flagged(pi, cell),
    ];
    _loadThumbs();
  }

  Future<void> _loadThumbs() async {
    if (_flagged.isEmpty) {
      if (mounted) setState(() => _loadingThumbs = false);
      return;
    }

    final pages = widget.cellResults.map((cr) => cr.crop.pageBytes).toList();
    final requests = _flagged.map((f) {
      final cr = widget.cellResults[f.pageIdx];
      return _ThumbReq(
        key: f.key,
        pageIdx: f.pageIdx,
        cropLeft: cr.crop.cropRect.left,
        cropTop: cr.crop.cropRect.top,
        cellW: cr.cellW,
        cellH: cr.cellH,
        col: f.cell.col,
        row: f.cell.row,
      );
    }).toList();

    final result = await compute(
      _extractThumbs,
      _ThumbBatchParams(pages: pages, requests: requests),
    );
    if (mounted) {
      setState(() {
        _thumbs.addAll(result);
        _loadingThumbs = false;
      });
    }
  }

  int get _unreviewedCount =>
      _flagged.where((f) => !_overrides.containsKey(f.key)).length;

  /// Build per-page override maps and apply them, returning corrected results.
  List<GridMatchResult> _buildUpdated() {
    final pageOvMaps = <int, Map<String, String?>>{};
    for (final f in _flagged) {
      if (_overrides.containsKey(f.key)) {
        final raw = _overrides[f.key]!;
        pageOvMaps
            .putIfAbsent(f.pageIdx, () => {})['${f.cell.col},${f.cell.row}'] =
            raw.isEmpty ? null : raw;
      }
    }
    return List.generate(widget.matchResults.length, (pi) {
      final ov = pageOvMaps[pi];
      if (ov == null || ov.isEmpty) return widget.matchResults[pi];
      return widget.matchResults[pi].withOverrides(ov);
    });
  }

  void _confirm() => Navigator.of(context).pop(_buildUpdated());

  Future<void> _showPicker(_Flagged f) async {
    final threads = widget.matchResults[f.pageIdx].threads;
    final currentDmc = _overrides.containsKey(f.key)
        ? (_overrides[f.key]!.isEmpty ? null : _overrides[f.key])
        : f.cell.dmcCode;

    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: _SymbolPicker(threads: threads, currentDmc: currentDmc),
      ),
    );

    // null → dismissed without selection; '' → empty; dmcCode → reassigned
    if (picked == null || !mounted) return;
    setState(() => _overrides[f.key] = picked);
  }

  static Color _confidenceColor(double c) {
    if (c < 0.3) return Colors.red.shade400;
    if (c < 0.5) return Colors.deepOrange.shade400;
    return Colors.orange.shade400;
  }

  static Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '').padRight(6, '0');
    return Color.fromARGB(
      255,
      int.parse(h.substring(0, 2), radix: 16),
      int.parse(h.substring(2, 4), radix: 16),
      int.parse(h.substring(4, 6), radix: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreviewed = _unreviewedCount;

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text('Review ${_flagged.length} flagged cells'),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingThumbs
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Status banner
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Text(
                    unreviewed == 0
                        ? 'All cells reviewed — tap Done to continue.'
                        : '$unreviewed of ${_flagged.length} cell(s) still unreviewed. '
                            'Tap any cell to reassign its symbol.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                // Cell grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: _flagged.length,
                    itemBuilder: (_, i) {
                      final f = _flagged[i];
                      final mr = widget.matchResults[f.pageIdx];
                      final isReviewed = _overrides.containsKey(f.key);
                      final raw = _overrides[f.key];
                      final displayDmc = isReviewed
                          ? (raw!.isEmpty ? null : raw)
                          : f.cell.dmcCode;
                      final thread = displayDmc == null
                          ? null
                          : mr.threads
                              .where((t) => t.dmcCode == displayDmc)
                              .firstOrNull;
                      final thumb = _thumbs[f.key];

                      return GestureDetector(
                        onTap: () => _showPicker(f),
                        child: _CellCard(
                          col: f.cell.col,
                          row: f.cell.row,
                          pageIdx: f.pageIdx,
                          confidence: f.cell.confidence,
                          thumb: thumb,
                          threadColor: thread != null
                              ? _hexColor(thread.colorHex)
                              : null,
                          dmcCode: displayDmc,
                          isReviewed: isReviewed,
                          confidenceColor:
                              _confidenceColor(f.cell.confidence),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Cell card ────────────────────────────────────────────────────────────────

class _CellCard extends StatelessWidget {
  final int col;
  final int row;
  final int pageIdx;
  final double confidence;
  final Uint8List? thumb;
  final Color? threadColor;
  final String? dmcCode;
  final bool isReviewed;
  final Color confidenceColor;

  const _CellCard({
    required this.col,
    required this.row,
    required this.pageIdx,
    required this.confidence,
    required this.thumb,
    required this.threadColor,
    required this.dmcCode,
    required this.isReviewed,
    required this.confidenceColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderColor =
        isReviewed ? Colors.green.shade600 : confidenceColor;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail area
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
              child: thumb != null
                  ? Image.memory(
                      thumb!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                    )
                  : const ColoredBox(color: Color(0xFF2A2A2A)),
            ),
          ),

          // Info strip
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              children: [
                // Color swatch or block icon
                if (threadColor != null)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: threadColor,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: Colors.grey.shade600, width: 0.5),
                    ),
                  )
                else
                  Icon(Icons.block,
                      size: 10, color: Colors.grey.shade500),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    dmcCode ?? '—',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontSize: 8, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isReviewed)
                  const Icon(Icons.check, size: 9, color: Colors.green),
              ],
            ),
          ),

          // Confidence badge (unreviewed only)
          if (!isReviewed)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Align(
                child: Text(
                  '${(confidence * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    color: confidenceColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Symbol picker bottom sheet ───────────────────────────────────────────────

class _SymbolPicker extends StatelessWidget {
  final List<ScannedThread> threads;

  /// Currently assigned DMC code, or null if the cell is currently empty.
  final String? currentDmc;

  const _SymbolPicker({required this.threads, this.currentDmc});

  static Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '').padRight(6, '0');
    return Color.fromARGB(
      255,
      int.parse(h.substring(0, 2), radix: 16),
      int.parse(h.substring(2, 4), radix: 16),
      int.parse(h.substring(4, 6), radix: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Assign symbol', style: theme.textTheme.titleMedium),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              // Empty / background option
              ListTile(
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF7F0),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.grey.shade400, width: 1),
                  ),
                  child: Icon(Icons.crop_square_outlined,
                      size: 18, color: Colors.grey.shade500),
                ),
                title: const Text('Empty (background)'),
                selected: currentDmc == null,
                selectedTileColor: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                onTap: () =>
                    Navigator.of(context).pop(''), // '' = empty
              ),
              const Divider(height: 1),
              // Thread options
              ...threads.map((t) {
                final color = _hexColor(t.colorHex);
                return ListTile(
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.grey.shade400, width: 1),
                    ),
                  ),
                  title: Text('DMC ${t.dmcCode}'),
                  subtitle: Text(t.name),
                  selected: currentDmc == t.dmcCode,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  onTap: () => Navigator.of(context).pop(t.dmcCode),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
