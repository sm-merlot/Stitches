import 'dart:math';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/aida_presets.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../services/skein_calculator.dart';

// ─── Share text builder ───────────────────────────────────────────────────────

/// Builds the markdown materials list string.
/// [threads] is a list of `(dmcCode, name, skeins)` records, already sorted.
String buildMaterialsListMarkdown({
  required String patternName,
  required Color aidaColor,
  required int aidaCount,
  required double widthCm,
  required double heightCm,
  required double widthIn,
  required double heightIn,
  required List<({String dmcCode, String name, int skeins})> threads,
}) {
  final buf = StringBuffer()
    ..writeln('# $patternName Materials List')
    ..writeln()
    ..writeln('- [ ] ${aidaColorLabel(aidaColor)} $aidaCount-count Aida min '
        '${widthCm.toStringAsFixed(1)} x ${heightCm.toStringAsFixed(1)} cm '
        '(${widthIn.toStringAsFixed(1)} x ${heightIn.toStringAsFixed(1)} in)');
  for (final t in threads) {
    buf.writeln(
        '- [ ] DMC ${t.dmcCode} ${t.name} x ${t.skeins} skein${t.skeins == 1 ? '' : 's'}');
  }
  return buf.toString();
}

// ─── Public entry point ───────────────────────────────────────────────────────

void showMaterialsList(BuildContext context, EditorState state) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 480,
          child: MaterialsListScreen(state: state),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MaterialsListScreen(state: state),
      ),
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class MaterialsListScreen extends StatefulWidget {
  final EditorState state;
  const MaterialsListScreen({super.key, required this.state});

  @override
  State<MaterialsListScreen> createState() => _MaterialsListScreenState();
}

class _MaterialsListScreenState extends State<MaterialsListScreen> {
  int _aidaCount = 14;
  int _strands = 2;
  final _shareButtonKey = GlobalKey();

  static const _aidaCounts = [11, 14, 16, 18, 28, 32];
  static const _strandOptions = [1, 2, 3, 4, 5, 6];

  // ─── Data helpers ─────────────────────────────────────────────────────────

  /// Unique threads to display — from composite cache if available, else pattern.threads.
  List<Thread> _threads() {
    final cache = widget.state.compositeResult?.compositeThreads;
    if (cache != null && cache.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in cache.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return widget.state.pattern.threads;
  }

  /// Cross-stitch equivalents per dmcCode (FullStitch=1.0, Half=0.5, Quarter=0.25).
  Map<String, double> _crossEquiv() {
    final compositeResult = widget.state.compositeResult;
    if (compositeResult != null) {
      return Map<String, double>.from(compositeResult.crossStitchEquiv);
    }
    // Fallback: no composite result yet — use raw single-layer stitches.
    final equiv = <String, double>{};
    for (final s in widget.state.pattern.stitches) {
      if (s is BackStitch) continue;
      final e = switch (s) {
        FullStitch() => 1.0,
        HalfStitch() => 0.5,
        HalfCrossStitch() => 0.5,
        QuarterStitch() => 0.25,
        QuarterCrossStitch() => 0.25,
        _ => 0.0,
      };
      if (e > 0) equiv[s.threadId] = (equiv[s.threadId] ?? 0) + e;
    }
    return equiv;
  }

  /// Backstitch Euclidean cell-unit length per dmcCode.
  Map<String, double> _backCells() {
    final compositeResult = widget.state.compositeResult;
    if (compositeResult != null) {
      return Map<String, double>.from(compositeResult.backStitchEquiv);
    }
    // Fallback: no composite result yet.
    final cells = <String, double>{};
    for (final s in widget.state.pattern.stitches) {
      if (s is! BackStitch) continue;
      final dx = s.x2 - s.x1;
      final dy = s.y2 - s.y1;
      cells[s.threadId] = (cells[s.threadId] ?? 0) + sqrt(dx * dx + dy * dy);
    }
    return cells;
  }

  // ─── Skein calculation ────────────────────────────────────────────────────

  int _skeins(
    String dmcCode,
    Map<String, double> crossEquiv,
    Map<String, double> backCells,
  ) =>
      calculateSkeins(
        dmcCode: dmcCode,
        crossEquiv: crossEquiv,
        backCells: backCells,
        aidaCount: _aidaCount,
        strands: _strands,
      );

  // ─── Aida size ────────────────────────────────────────────────────────────

  ({double widthCm, double heightCm, double widthIn, double heightIn})
      get _aidaSize {
    final p = widget.state.pattern;
    final wCm = (p.width / _aidaCount) * 2.54 + 10;
    final hCm = (p.height / _aidaCount) * 2.54 + 10;
    return (
      widthCm: wCm,
      heightCm: hCm,
      widthIn: wCm / 2.54,
      heightIn: hCm / 2.54,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _threadName(Thread t) {
    // Composite blended threads may lack a real name — fall back to pattern threads
    return widget.state.pattern.threadByCode(t.dmcCode)?.name ?? t.name;
  }

  List<Thread> _sorted(List<Thread> threads) {
    return [...threads]..sort((a, b) {
        final ia = int.tryParse(a.dmcCode) ?? 999999;
        final ib = int.tryParse(b.dmcCode) ?? 999999;
        return ia != ib ? ia.compareTo(ib) : a.dmcCode.compareTo(b.dmcCode);
      });
  }

  // ─── Share ────────────────────────────────────────────────────────────────

  void _share(
    List<Thread> sorted,
    Map<String, double> crossEquiv,
    Map<String, double> backCells,
  ) {
    final p = widget.state.pattern;
    final s = _aidaSize;

    final text = buildMaterialsListMarkdown(
      patternName: p.name,
      aidaColor: p.aidaColor,
      aidaCount: _aidaCount,
      widthCm: s.widthCm,
      heightCm: s.heightCm,
      widthIn: s.widthIn,
      heightIn: s.heightIn,
      threads: sorted
          .map((t) => (
                dmcCode: t.dmcCode,
                name: _threadName(t),
                skeins: _skeins(t.dmcCode, crossEquiv, backCells),
              ))
          .toList(),
    );

    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    SharePlus.instance.share(ShareParams(
      title: '${p.name} - Materials List',
      subject: '${p.name} - Materials List',
      text: text,
      sharePositionOrigin: origin,
    ));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.shortestSide >= 600;

    final threads = _threads();
    final sorted = _sorted(threads);
    final crossEquiv = _crossEquiv();
    final backCells = _backCells();
    final size = _aidaSize;
    final totalSkeins = sorted.fold<int>(
        0, (sum, t) => sum + _skeins(t.dmcCode, crossEquiv, backCells));

    // ── Controls ──────────────────────────────────────────────────────────────
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          const Text('Aida count:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _aidaCount,
            isDense: true,
            items: _aidaCounts
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _aidaCount = v);
            },
          ),
          const SizedBox(width: 20),
          const Text('Strands:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _strands,
            isDense: true,
            items: _strandOptions
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _strands = v);
            },
          ),
        ],
      ),
    );

    // ── Aida size row ─────────────────────────────────────────────────────────
    final aidaRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: widget.state.pattern.aidaColor,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Aida: at least '
              '${size.widthCm.toStringAsFixed(1)} × ${size.heightCm.toStringAsFixed(1)} cm  '
              '(${size.widthIn.toStringAsFixed(1)} × ${size.heightIn.toStringAsFixed(1)} in)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Tooltip(
            message:
                'Includes a 5 cm (2 in) border on each side for framing and mounting.',
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    // ── Table header ──────────────────────────────────────────────────────────
    const tableHeader = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 36),
          SizedBox(
            width: 52,
            child: Text('DMC',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text('Name',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 52,
            child: Text('Skeins',
                textAlign: TextAlign.right,
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    // ── Thread list ───────────────────────────────────────────────────────────
    final listView = ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final t = sorted[i];
        final n = _skeins(t.dmcCode, crossEquiv, backCells);
        final textColor =
            t.color.computeLuminance() > 0.35 ? Colors.black : Colors.white;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              // Swatch with symbol
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.color,
                  borderRadius: BorderRadius.circular(5),
                  border:
                      Border.all(color: Colors.grey.shade400, width: 1),
                ),
                alignment: Alignment.center,
                child: t.symbol.isNotEmpty
                    ? Text(t.symbol,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            height: 1.0))
                    : null,
              ),
              const SizedBox(width: 8),
              // DMC code
              SizedBox(
                width: 44,
                child:
                    Text(t.dmcCode, style: const TextStyle(fontSize: 13)),
              ),
              // Name
              Expanded(
                child: Text(
                  _threadName(t),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Skeins
              SizedBox(
                width: 52,
                child: Text(
                  '$n',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        );
      },
    );

    // ── Footer ────────────────────────────────────────────────────────────────
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      child: Row(
        children: [
          Text(
            '${sorted.length} thread${sorted.length == 1 ? '' : 's'}  ·  '
            '$totalSkeins skein${totalSkeins == 1 ? '' : 's'}',
            style: TextStyle(
                fontSize: 13,
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          const Spacer(),
          FilledButton.icon(
            key: _shareButtonKey,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Share'),
            onPressed: () => _share(sorted, crossEquiv, backCells),
          ),
        ],
      ),
    );

    // ── Layout: dialog vs full-screen ─────────────────────────────────────────
    if (isWide) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                    child: Text('Materials List',
                        style: theme.textTheme.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          controls,
          aidaRow,
          const Divider(height: 1),
          tableHeader,
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: listView,
          ),
          const Divider(height: 1),
          footer,
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Materials List')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          controls,
          aidaRow,
          const Divider(height: 1),
          tableHeader,
          const Divider(height: 1),
          Expanded(child: listView),
          const Divider(height: 1),
          SafeArea(top: false, child: footer),
        ],
      ),
    );
  }
}
