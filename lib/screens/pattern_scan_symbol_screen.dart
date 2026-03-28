import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../data/dmc_colors.dart';
import '../services/grid_symbol_matcher.dart';
import 'pattern_scan_cell_screen.dart';

part 'pattern_scan_symbol_screen_widgets.dart';

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

