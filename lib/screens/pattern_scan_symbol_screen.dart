import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../data/dmc_colors.dart';
import '../services/grid_symbol_matcher.dart';
import 'pattern_scan_cell_screen.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

/// Full-screen UI where the user identifies each unique symbol by tapping
/// representative cells in the grid and assigning DMC codes.
///
/// The user taps any cell that contains a unique symbol, picks the matching DMC
/// code from the search dialog, and repeats for every distinct symbol type.
/// Multiple taps for the same code are allowed and improve matching accuracy.
///
/// Pops with [List<SymbolSample>] (one entry per unique DMC code), or null if
/// the user cancelled.
class PatternScanSymbolScreen extends StatefulWidget {
  final List<GridCellResult> cellResults;
  final List<Uint8List> legendPages;

  const PatternScanSymbolScreen({
    super.key,
    required this.cellResults,
    required this.legendPages,
  });

  static Future<List<SymbolSample>?> show(
    BuildContext context, {
    required List<GridCellResult> cellResults,
    required List<Uint8List> legendPages,
  }) =>
      Navigator.of(context).push<List<SymbolSample>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PatternScanSymbolScreen(
            cellResults: cellResults,
            legendPages: legendPages,
          ),
        ),
      );

  @override
  State<PatternScanSymbolScreen> createState() =>
      _PatternScanSymbolScreenState();
}

// ─── Screen state ─────────────────────────────────────────────────────────────

class _PatternScanSymbolScreenState extends State<PatternScanSymbolScreen> {
  int _pageIndex = 0;
  ui.Image? _pageImage;
  bool _imageLoading = false;
  bool _isCropping = false;

  /// The DMC code currently being sampled. Tapping a cell adds a crop for this
  /// code without reopening the picker. Null = picker will be shown on next tap.
  String? _activeDmcCode;

  /// Accumulated sample data, keyed by DMC code.
  final Map<String, _PendingSample> _pending = {};

  /// Averaged preview PNG for each DMC code, computed asynchronously after
  /// each new crop is added.
  final Map<String, Uint8List> _previewBytes = {};

  /// "pageIdx,col,row" → dmcCode — tracks which cells have been sampled for
  /// rendering the highlight overlay.
  final Map<String, String> _cellDmc = {};

  @override
  void initState() {
    super.initState();
    _loadPage(0);
  }

  @override
  void dispose() {
    _pageImage?.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int index) async {
    if (_imageLoading) return;
    _imageLoading = true;
    _pageImage?.dispose();
    setState(() => _pageImage = null);

    final bytes = widget.cellResults[index].crop.pageBytes;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();

    _imageLoading = false;
    if (mounted) setState(() => _pageImage = frame.image);
  }

  Future<void> _onTapCell(int col, int row) async {
    if (_isCropping) return;
    final cellResult = widget.cellResults[_pageIndex];
    if (col < 0 || col >= cellResult.columns || row < 0 || row >= cellResult.rows) {
      return;
    }
    if (!mounted) return;

    // If no symbol is active, ask the user to pick a DMC code first.
    if (_activeDmcCode == null) {
      await _startNewSymbol();
      if (_activeDmcCode == null) return; // user cancelled
    }

    final code = _activeDmcCode!;
    setState(() => _isCropping = true);

    // Crop the selected cell from the full-resolution page image.
    final cropBytes = await compute(_cropCellBytes, _CropParams(
      pageBytes: cellResult.crop.pageBytes,
      left: (cellResult.crop.cropRect.left +
             cellResult.cellOffsetX +
             col * cellResult.cellW).round(),
      top:  (cellResult.crop.cropRect.top +
             cellResult.cellOffsetY +
             row * cellResult.cellH).round(),
      width:  cellResult.cellW.round().clamp(1, 9999),
      height: cellResult.cellH.round().clamp(1, 9999),
    ));

    if (!mounted) return;

    setState(() {
      _isCropping = false;
      if (cropBytes != null) {
        _pending[code]!.crops.add(cropBytes);
      }
      _cellDmc['$_pageIndex,$col,$row'] = code;
    });

    if (cropBytes != null) _updatePreview(code);
  }

  /// Open the DMC picker, create a new [_PendingSample] for the chosen code,
  /// and make it the active symbol.
  Future<void> _startNewSymbol() async {
    if (!mounted) return;
    final picked = await showDialog<DmcColor>(
      context: context,
      builder: (_) => const _DmcPickerDialog(),
    );
    if (picked == null || !mounted) return;

    final colorHex = _dmcColorToHex(picked.color);
    setState(() {
      _activeDmcCode = picked.code;
      _pending.putIfAbsent(
        picked.code,
        () => _PendingSample(dmcCode: picked.code, colorHex: colorHex),
      );
    });
  }

  /// Compute the averaged preview image for [dmcCode] in the background and
  /// store the result in [_previewBytes].
  Future<void> _updatePreview(String dmcCode) async {
    final crops = List<Uint8List>.from(_pending[dmcCode]?.crops ?? []);
    if (crops.isEmpty) return;
    final bytes = await compute(_buildAveragePreview, crops);
    if (mounted && bytes != null) {
      setState(() => _previewBytes[dmcCode] = bytes);
    }
  }

  void _removeSample(String dmcCode) {
    setState(() {
      _pending.remove(dmcCode);
      _previewBytes.remove(dmcCode);
      _cellDmc.removeWhere((_, v) => v == dmcCode);
      if (_activeDmcCode == dmcCode) {
        _activeDmcCode = _pending.keys.firstOrNull;
      }
    });
  }

  Future<void> _confirm() async {
    final sampleCount = _pending.values.where((s) => s.crops.isNotEmpty).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start scanning?'),
        content: Text(
          'You have $sampleCount symbol type${sampleCount == 1 ? '' : 's'} mapped. '
          'The app will now match every cell in the grid against these samples.\n\n'
          'Make sure you have sampled all unique symbols before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Scan now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final samples = _pending.values
        .where((s) => s.crops.isNotEmpty)
        .map((s) => SymbolSample(
              dmcCode: s.dmcCode,
              colorHex: s.colorHex,
              crops: List.unmodifiable(s.crops),
            ))
        .toList();
    Navigator.of(context).pop(samples);
  }

  void _switchPage(int newIndex) {
    setState(() => _pageIndex = newIndex);
    _loadPage(newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cellResult = widget.cellResults[_pageIndex];
    final pageCount = widget.cellResults.length;
    final validSamples =
        _pending.values.where((s) => s.crops.isNotEmpty).length;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(pageCount > 1
            ? 'Identify symbols — page ${_pageIndex + 1} of $pageCount'
            : 'Identify symbols'),
        actions: [
          if (widget.legendPages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Show legend for reference',
              onPressed: () => _showLegend(context),
            ),
          if (_isCropping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            )
          else
            TextButton(
              onPressed: validSamples > 0 ? _confirm : null,
              child: Text(
                'Done',
                style: TextStyle(
                  color: validSamples > 0 ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _activeDmcCode == null
                  ? 'Tap a cell to identify its symbol and choose a DMC colour. '
                    'Tap the legend button to view the colour key.'
                  : 'Adding samples for DMC $_activeDmcCode. '
                    'Keep tapping cells with the same symbol, or tap + to start a new one.',
              style: theme.textTheme.bodySmall,
            ),
          ),

          // Main grid view
          Expanded(
            child: _pageImage == null
                ? const Center(child: CircularProgressIndicator())
                : _GridTapView(
                    key: ValueKey(_pageIndex),
                    image: _pageImage!,
                    cellResult: cellResult,
                    pageIndex: _pageIndex,
                    cellDmc: _cellDmc,
                    pending: _pending,
                    onTapCell: _onTapCell,
                  ),
          ),

          // Sample chips — always visible so the user can switch the active symbol
          Container(
            constraints: const BoxConstraints(maxHeight: 88),
            color: Colors.black54,
            child: _SampleRow(
              pending: _pending,
              previewBytes: _previewBytes,
              activeDmcCode: _activeDmcCode,
              onSelect: (code) => setState(() => _activeDmcCode = code),
              onRemove: _removeSample,
              onAddNew: _startNewSymbol,
            ),
          ),

          // Page navigation (multi-page only)
          if (pageCount > 1)
            Container(
              color: Colors.black87,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: Colors.white,
                    onPressed:
                        _pageIndex > 0 ? () => _switchPage(_pageIndex - 1) : null,
                  ),
                  Text(
                    'Page ${_pageIndex + 1} of $pageCount',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: Colors.white,
                    onPressed: _pageIndex < pageCount - 1
                        ? () => _switchPage(_pageIndex + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showLegend(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2A2A2A),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.2,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => ListView.builder(
          controller: controller,
          itemCount: widget.legendPages.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.all(8),
            child: _LegendPageImage(bytes: widget.legendPages[i]),
          ),
        ),
      ),
    );
  }
}

// ─── Grid tap view ────────────────────────────────────────────────────────────

class _GridTapView extends StatefulWidget {
  final ui.Image image;
  final GridCellResult cellResult;
  final int pageIndex;
  final Map<String, String> cellDmc;
  final Map<String, _PendingSample> pending;
  final void Function(int col, int row) onTapCell;

  const _GridTapView({
    super.key,
    required this.image,
    required this.cellResult,
    required this.pageIndex,
    required this.cellDmc,
    required this.pending,
    required this.onTapCell,
  });

  @override
  State<_GridTapView> createState() => _GridTapViewState();
}

class _GridTapViewState extends State<_GridTapView> {
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  bool _initialized = false;

  // Scale gesture tracking
  double? _zoomAtStart;
  Offset? _focalInImageAtStart;

  void _initFit(BoxConstraints c) {
    if (_initialized) return;
    _initialized = true;
    final cropW = widget.cellResult.crop.cropRect.width;
    final cropH = widget.cellResult.crop.cropRect.height;
    _zoom = math.min(c.maxWidth / cropW, c.maxHeight / cropH);
    _pan = Offset(
      (c.maxWidth - cropW * _zoom) / 2,
      (c.maxHeight - cropH * _zoom) / 2,
    );
  }

  /// Convert a point in widget space to image (crop-relative) space.
  Offset _screenToImage(Offset screenPos) =>
      Offset((screenPos.dx - _pan.dx) / _zoom, (screenPos.dy - _pan.dy) / _zoom);

  (int col, int row) _tapToCell(Offset screenPos) {
    final cr = widget.cellResult;
    final imgPos = _screenToImage(screenPos);
    final col = ((imgPos.dx - cr.cellOffsetX) / cr.cellW).floor();
    final row = ((imgPos.dy - cr.cellOffsetY) / cr.cellH).floor();
    return (col, row);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      _initFit(constraints);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (d) {
          _zoomAtStart = _zoom;
          _focalInImageAtStart = _screenToImage(d.localFocalPoint);
        },
        onScaleUpdate: (d) {
          final newZoom = (_zoomAtStart! * d.scale).clamp(0.5, 12.0);
          final focal = _focalInImageAtStart!;
          setState(() {
            _zoom = newZoom;
            _pan = d.localFocalPoint -
                Offset(focal.dx * newZoom, focal.dy * newZoom);
          });
        },
        onTapUp: (d) {
          final (col, row) = _tapToCell(d.localPosition);
          widget.onTapCell(col, row);
        },
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _GridSymbolPainter(
            image: widget.image,
            cellResult: widget.cellResult,
            pageIndex: widget.pageIndex,
            cellDmc: widget.cellDmc,
            pending: widget.pending,
            zoom: _zoom,
            pan: _pan,
          ),
        ),
      );
    });
  }
}

// ─── Grid painter ─────────────────────────────────────────────────────────────

class _GridSymbolPainter extends CustomPainter {
  final ui.Image image;
  final GridCellResult cellResult;
  final int pageIndex;
  final Map<String, String> cellDmc;
  final Map<String, _PendingSample> pending;
  final double zoom;
  final Offset pan;

  const _GridSymbolPainter({
    required this.image,
    required this.cellResult,
    required this.pageIndex,
    required this.cellDmc,
    required this.pending,
    required this.zoom,
    required this.pan,
  });

  /// Convert a crop-relative image rect to widget (screen) space.
  Rect _cropRectToScreen(Rect r) => Rect.fromLTWH(
        pan.dx + r.left * zoom,
        pan.dy + r.top * zoom,
        r.width * zoom,
        r.height * zoom,
      );

  /// Screen rect for cell at (col, row).
  Rect _cellScreenRect(int col, int row) {
    final cx = cellResult.cellOffsetX + col * cellResult.cellW;
    final cy = cellResult.cellOffsetY + row * cellResult.cellH;
    return Rect.fromLTWH(
      pan.dx + cx * zoom,
      pan.dy + cy * zoom,
      cellResult.cellW * zoom,
      cellResult.cellH * zoom,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the crop region of the full-page image.
    final cropRect = cellResult.crop.cropRect;
    final destRect = _cropRectToScreen(
        Rect.fromLTWH(0, 0, cropRect.width, cropRect.height));
    canvas.drawImageRect(image, cropRect, destRect, Paint());

    // 2. Semi-transparent cell grid overlay.
    final gridPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final left = pan.dx + cellResult.cellOffsetX * zoom;
    final top  = pan.dy + cellResult.cellOffsetY * zoom;
    final gridW = cellResult.columns * cellResult.cellW * zoom;
    final gridH = cellResult.rows    * cellResult.cellH * zoom;

    for (int r = 0; r <= cellResult.rows; r++) {
      final y = top + r * cellResult.cellH * zoom;
      canvas.drawLine(Offset(left, y), Offset(left + gridW, y), gridPaint);
    }
    for (int c = 0; c <= cellResult.columns; c++) {
      final x = left + c * cellResult.cellW * zoom;
      canvas.drawLine(Offset(x, top), Offset(x, top + gridH), gridPaint);
    }

    // 3. Highlight sampled cells with their DMC colour.
    for (final entry in cellDmc.entries) {
      final parts = entry.key.split(',');
      if (parts.length != 3) continue;
      final pi = int.tryParse(parts[0]);
      if (pi != pageIndex) continue;
      final col = int.tryParse(parts[1]);
      final row = int.tryParse(parts[2]);
      if (col == null || row == null) continue;

      final sample = pending[entry.value];
      if (sample == null) continue;

      final hex = sample.colorHex.replaceAll('#', '');
      final color = Color(int.parse('FF$hex', radix: 16));
      final rect = _cellScreenRect(col, row);

      canvas.drawRect(rect,
          Paint()..color = color.withValues(alpha: 0.45));
      canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_GridSymbolPainter old) =>
      old.cellDmc.length != cellDmc.length ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.pageIndex != pageIndex ||
      old.pending.length != pending.length;
}

// ─── Sample row ───────────────────────────────────────────────────────────────

class _SampleRow extends StatelessWidget {
  final Map<String, _PendingSample> pending;
  final Map<String, Uint8List> previewBytes;
  final String? activeDmcCode;
  final void Function(String dmcCode) onSelect;
  final void Function(String dmcCode) onRemove;
  final VoidCallback onAddNew;

  const _SampleRow({
    required this.pending,
    required this.previewBytes,
    required this.activeDmcCode,
    required this.onSelect,
    required this.onRemove,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final samples = pending.values.toList();
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      // +1 for the "New symbol" chip at the end
      itemCount: samples.length + 1,
      itemBuilder: (_, i) {
        // "New symbol" chip
        if (i == samples.length) {
          return GestureDetector(
            onTap: onAddNew,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white30),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, color: Colors.white70, size: 16),
                  SizedBox(width: 4),
                  Text('New symbol',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          );
        }

        final s = samples[i];
        final isActive = s.dmcCode == activeDmcCode;
        final hex = s.colorHex.replaceAll('#', '');
        final dmcColor = Color(int.parse('FF$hex', radix: 16));
        final count = s.crops.length;
        final preview = previewBytes[s.dmcCode];

        return GestureDetector(
          onTap: () => onSelect(s.dmcCode),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isActive ? Colors.white12 : Colors.black45,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? Colors.cyan : Colors.white24,
                width: isActive ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Preview: averaged cell render, or colour swatch if not ready
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: preview != null
                        ? Image.memory(preview, fit: BoxFit.contain)
                        : Container(
                            color: dmcColor,
                            child: const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.white54),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: dmcColor,
                            border: Border.all(color: Colors.white38),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Text(s.dmcCode,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Text('$count sample${count == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => onRemove(s.dmcCode),
                  child: const Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── DMC picker dialog ────────────────────────────────────────────────────────

class _DmcPickerDialog extends StatefulWidget {
  const _DmcPickerDialog();

  @override
  State<_DmcPickerDialog> createState() => _DmcPickerDialogState();
}

class _DmcPickerDialogState extends State<_DmcPickerDialog> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<DmcColor> get _filtered {
    if (_query.isEmpty) return dmcColors;
    final q = _query.toLowerCase();
    return dmcColors
        .where((c) =>
            c.code.toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Dialog(
      child: SizedBox(
        width: 360,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search DMC code or name…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c.color,
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    title: Text('${c.code}  ${c.name}',
                        style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Legend page image ────────────────────────────────────────────────────────

class _LegendPageImage extends StatefulWidget {
  final Uint8List bytes;
  const _LegendPageImage({required this.bytes});

  @override
  State<_LegendPageImage> createState() => _LegendPageImageState();
}

class _LegendPageImageState extends State<_LegendPageImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final im = _image;
    if (im == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    return RawImage(image: im, fit: BoxFit.contain);
  }
}

// ─── Helper types ─────────────────────────────────────────────────────────────

class _PendingSample {
  final String dmcCode;
  final String colorHex;
  final List<Uint8List> crops;

  _PendingSample({required this.dmcCode, required this.colorHex})
      : crops = [];
}

// ─── Colour helper ────────────────────────────────────────────────────────────

String _dmcColorToHex(Color color) {
  final v = color.toARGB32();
  final r = (v >> 16) & 0xFF;
  final g = (v >> 8)  & 0xFF;
  final b =  v        & 0xFF;
  return '#${r.toRadixString(16).padLeft(2, '0')}'
         '${g.toRadixString(16).padLeft(2, '0')}'
         '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
}

// ─── Isolate helpers ──────────────────────────────────────────────────────────

class _CropParams {
  final Uint8List pageBytes;
  final int left;
  final int top;
  final int width;
  final int height;

  const _CropParams({
    required this.pageBytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// Top-level function for [compute]: averages a list of same-sized PNG cell
/// crops into one representative preview image.
Uint8List? _buildAveragePreview(List<Uint8List> crops) {
  if (crops.isEmpty) return null;
  final images = crops
      .map((b) => img.decodePng(b))
      .whereType<img.Image>()
      .toList();
  if (images.isEmpty) return null;
  if (images.length == 1) return Uint8List.fromList(img.encodePng(images[0]));

  final w = images[0].width;
  final h = images[0].height;
  final out = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int rSum = 0, gSum = 0, bSum = 0;
      for (final im in images) {
        final px = im.getPixel(x, y);
        rSum += px.r.toInt();
        gSum += px.g.toInt();
        bSum += px.b.toInt();
      }
      final n = images.length;
      out.setPixel(x, y, img.ColorRgb8(rSum ~/ n, gSum ~/ n, bSum ~/ n));
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// Top-level function for [compute]: crops a cell from the full page PNG.
Uint8List? _cropCellBytes(_CropParams p) {
  final page = img.decodePng(p.pageBytes);
  if (page == null) return null;

  final x = p.left.clamp(0, page.width - 1);
  final y = p.top.clamp(0, page.height - 1);
  final w = math.min(p.width, page.width - x);
  final h = math.min(p.height, page.height - y);
  if (w <= 0 || h <= 0) return null;

  final cropped = img.copyCrop(page, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodePng(cropped));
}
