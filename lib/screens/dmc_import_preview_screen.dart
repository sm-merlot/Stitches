import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../data/dmc_colors.dart';
import '../services/color_space.dart';
import '../services/sprite_importer.dart';

/// Full-screen DMC-matched preview shown before the user commits to importing.
///
/// Renders the cropped region with every pixel (or palette slot) replaced by
/// its nearest DMC thread colour under the chosen algorithm.
///
/// The user can:
///   - Switch algorithms and see the preview update in real time.
///   - Browse each palette and see which DMC colours its slots map to.
///   - Confirm ("Add to Snippets") or cancel.
///
/// Pops with `true` (confirmed) or `false` / `null` (cancelled).
/// On confirm the calling screen should proceed with its import; the active
/// algorithm is already set on [SpriteImporter.matchAlgorithm].
class DmcImportPreviewScreen extends StatefulWidget {
  final img.Image image;
  final Rect region;

  /// Raw pixel colours per palette strip.  Empty = auto-detect all DMC colours.
  final List<List<Color>> paletteStrips;
  final String snippetName;

  const DmcImportPreviewScreen({
    super.key,
    required this.image,
    required this.region,
    required this.paletteStrips,
    required this.snippetName,
  });

  @override
  State<DmcImportPreviewScreen> createState() => _DmcImportPreviewScreenState();
}

class _DmcImportPreviewScreenState extends State<DmcImportPreviewScreen> {
  MatchAlgorithm _algorithm = SpriteImporter.matchAlgorithm;
  int _activePalette = 0;
  Uint8List? _previewBytes;

  // [paletteIndex][slotIndex] → matched DmcColor (null if unmatched)
  late List<List<DmcColor?>> _dmcSlots;

  @override
  void initState() {
    super.initState();
    _recomputeAll();
  }

  // ── Compute helpers ─────────────────────────────────────────────────────────

  void _recomputeAll() {
    _dmcSlots = widget.paletteStrips.map((strip) {
      return strip.map((c) => SpriteImporter.matchPixel(
            (c.r * 255).round(),
            (c.g * 255).round(),
            (c.b * 255).round(),
            255,
          )).toList();
    }).toList();
    _renderPreview();
  }

  void _renderPreview() {
    if (widget.paletteStrips.isEmpty) {
      // Auto mode: every pixel matched independently.
      _previewBytes =
          SpriteImporter.renderAsDmcMatched(widget.image, widget.region);
    } else {
      final baseRaw = widget.paletteStrips[0];
      final idx = _activePalette.clamp(0, widget.paletteStrips.length - 1);
      final dmcColours = _resolvedDmcColours(idx);
      _previewBytes = SpriteImporter.renderCropWithPalette(
        widget.image,
        widget.region,
        baseRaw,
        outputPalette: dmcColours.isEmpty ? null : dmcColours,
      );
    }
  }

  /// DMC [Color]s for palette [i], falling back to the raw strip value for
  /// unmatched slots.
  List<Color> _resolvedDmcColours(int i) {
    if (i >= widget.paletteStrips.length) return [];
    final raw = widget.paletteStrips[i];
    final slots = i < _dmcSlots.length ? _dmcSlots[i] : <DmcColor?>[];
    return List.generate(raw.length, (j) {
      final dmc = j < slots.length ? slots[j] : null;
      return dmc?.color ?? raw[j];
    });
  }

  void _onAlgorithmChanged(MatchAlgorithm algo) {
    setState(() {
      _algorithm = algo;
      SpriteImporter.matchAlgorithm = algo; // clears match cache
      _recomputeAll();
    });
  }

  void _onPaletteSelected(int index) {
    setState(() {
      _activePalette = index;
      _renderPreview();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('DMC Preview — ${widget.snippetName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Add to Snippets'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          Expanded(child: _buildPreviewArea(theme)),
          VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
          SizedBox(width: 300, child: _buildSidePanel(theme)),
        ],
      ),
    );
  }

  // ── Preview area ────────────────────────────────────────────────────────────

  Widget _buildPreviewArea(ThemeData theme) {
    return Stack(
      children: [
        CustomPaint(
          painter: _CheckerPainter(),
          child: const SizedBox.expand(),
        ),
        if (_previewBytes != null)
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 40.0,
            child: Center(
              child: Image.memory(
                _previewBytes!,
                filterQuality: FilterQuality.none,
              ),
            ),
          )
        else
          Center(
            child: Text(
              'Rendering…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.disabledColor),
            ),
          ),
      ],
    );
  }

  // ── Side panel ──────────────────────────────────────────────────────────────

  Widget _buildSidePanel(ThemeData theme) {
    final hasStrips = widget.paletteStrips.isNotEmpty;
    return Column(
      children: [
        // ── Algorithm ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Colour matching algorithm',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<MatchAlgorithm>(
                initialValue: _algorithm,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                ),
                style: theme.textTheme.bodySmall,
                items: MatchAlgorithm.values
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(matchAlgorithmLabel(a),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (a) {
                  if (a != null) _onAlgorithmChanged(a);
                },
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: theme.dividerColor),

        // ── Palette list ─────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  hasStrips ? 'Palettes' : 'Auto-matched colours',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (!hasStrips)
                  Text(
                    'Each pixel is matched individually to its nearest DMC thread colour.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  )
                else
                  for (int i = 0; i < widget.paletteStrips.length; i++)
                    _buildPaletteCard(i, theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Palette card ─────────────────────────────────────────────────────────────

  Widget _buildPaletteCard(int index, ThemeData theme) {
    final isActive = _activePalette == index;
    final rawStrip = widget.paletteStrips[index];
    final slots =
        index < _dmcSlots.length ? _dmcSlots[index] : <DmcColor?>[];

    return GestureDetector(
      onTap: () => _onPaletteSelected(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color:
                isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Palette ${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    isActive ? theme.colorScheme.primary : null,
                fontWeight: isActive ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(height: 6),

            // Two rows: raw colours on top, matched DMC below.
            _buildSwatchRow(
              label: 'Source',
              colours: rawStrip,
              labels: List.generate(rawStrip.length, (_) => null),
              theme: theme,
            ),
            const SizedBox(height: 4),
            _buildSwatchRow(
              label: 'DMC',
              colours: List.generate(rawStrip.length, (j) {
                final dmc = j < slots.length ? slots[j] : null;
                return dmc?.color ?? rawStrip[j];
              }),
              labels: List.generate(rawStrip.length, (j) {
                return j < slots.length ? slots[j]?.code : null;
              }),
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwatchRow({
    required String label,
    required List<Color> colours,
    required List<String?> labels,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int j = 0; j < colours.length; j++)
                  Tooltip(
                    message: labels[j] ?? '',
                    child: Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: colours[j],
                        border: Border.all(color: Colors.black26, width: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Checkerboard background ───────────────────────────────────────────────────

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tileSize = 8.0;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y * tileSize < size.height; y++) {
      for (var x = 0; x * tileSize < size.width; x++) {
        paint.color = (x + y).isEven
            ? const Color(0xFFCCCCCC)
            : const Color(0xFF999999);
        canvas.drawRect(
          Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter _) => false;
}

