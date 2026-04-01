import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/pattern.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../services/format_service.dart';
import '../services/pdf_service.dart';
import '../utils/snackbars.dart';

/// Shows a format-picker dialog then exports the pattern.
/// Returns true if the export succeeded.
/// If [notifier] is provided, auto-assigning symbols will persist them to the
/// pattern; otherwise symbols are applied only for this export.
Future<bool> showExportDialog(
    BuildContext context, CrossStitchPattern pattern,
    {bool useDmc = true, EditorNotifier? notifier}) async {
  final choice = await showDialog<_ExportChoice>(
    context: context,
    builder: (_) => const _ExportPickerDialog(),
  );
  if (choice == null || !context.mounted) return false;

  try {
    if (choice == _ExportChoice.pdf) {
      final missing = _missingSymbolAssignments(pattern);
      CrossStitchPattern exportPattern = pattern;

      if (missing.isNotEmpty) {
        if (!context.mounted) return false;
        final resolution = await showDialog<_SymbolResolution>(
          context: context,
          builder: (_) => _MissingSymbolsDialog(
            threads: pattern.threads
                .where((t) => missing.containsKey(t.dmcCode))
                .toList(),
            assignments: missing,
            useDmc: useDmc,
          ),
        );
        if (!context.mounted) return false;
        switch (resolution) {
          case null:
          case _SymbolResolution.cancel:
            return false;
          case _SymbolResolution.autoAssign:
            // Permanently persist via notifier when available
            if (notifier != null) {
              for (final entry in missing.entries) {
                if (entry.value.isNotEmpty) {
                  notifier.setThreadSymbol(entry.key, entry.value);
                }
              }
            }
            // Always use the assigned symbols for this export
            exportPattern = pattern.copyWith(
              threads: pattern.threads.map((t) {
                final proposed = missing[t.dmcCode];
                return (proposed != null && proposed.isNotEmpty)
                    ? t.copyWith(symbol: proposed)
                    : t;
              }).toList(),
            );
          case _SymbolResolution.exportAnyway:
            break; // proceed with current pattern (blanks in chart)
        }
      }

      await PdfService.exportPattern(exportPattern, useDmc: useDmc);
      return true;
    }

    // For cross-stitch formats, ask the user for a save path.
    final format = choice.format!;
    final suggested = pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final path = await FilePicker.platform.saveFile(
      fileName: '$suggested.${format.extension}',
      type: FileType.custom,
      allowedExtensions: [format.extension],
    );
    if (path == null) return false;

    final finalPath = path.endsWith('.${format.extension}')
        ? path
        : '$path.${format.extension}';
    await FormatService.exportFile(pattern, finalPath, format);

    if (context.mounted) {
      showSuccess(
          context, 'Exported as ${finalPath.split(Platform.pathSeparator).last}');
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'Export failed: $e');
    return false;
  }
}

// ─── Missing symbol helpers ───────────────────────────────────────────────────

/// Returns a map of dmcCode → proposed symbol for every thread that has no
/// symbol. The proposed symbol is the next available from [kPatternSymbols],
/// or an empty string if the pool is exhausted.
Map<String, String> _missingSymbolAssignments(CrossStitchPattern pattern) {
  final used =
      pattern.threads.map((t) => t.symbol).where((s) => s.isNotEmpty).toSet();
  final result = <String, String>{};
  for (final t in pattern.threads) {
    if (!symbolIsVisible(t.symbol)) {
      String proposed = '';
      for (final s in kPatternSymbols) {
        if (!used.contains(s)) {
          proposed = s;
          used.add(s);
          break;
        }
      }
      result[t.dmcCode] = proposed;
    }
  }
  return result;
}

enum _SymbolResolution { autoAssign, exportAnyway, cancel }

// ─── Missing symbols dialog ───────────────────────────────────────────────────

class _MissingSymbolsDialog extends StatelessWidget {
  final List<Thread> threads;
  final Map<String, String> assignments;
  final bool useDmc;

  const _MissingSymbolsDialog({
    required this.threads,
    required this.assignments,
    required this.useDmc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 8),
          const Text('Missing symbols'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following colours have no symbol assigned. '
              'They will appear as blank squares in the PDF chart.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(width: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Colour',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6))),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('Would assign',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),
            // Thread rows
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  children: threads.map((t) => _threadRow(t, theme)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_SymbolResolution.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_SymbolResolution.exportAnyway),
          child: const Text('Export without symbols'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_SymbolResolution.autoAssign),
          child: const Text('Auto-assign'),
        ),
      ],
    );
  }

  Widget _threadRow(Thread t, ThemeData theme) {
    final proposed = assignments[t.dmcCode] ?? '';
    final swatchText =
        t.color.computeLuminance() > 0.35 ? Colors.black : Colors.white;
    final code = useDmc
        ? t.dmcCode
        : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Row(
        children: [
          // Current swatch (no symbol — warning border)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: t.color,
              borderRadius: BorderRadius.circular(5),
              border:
                  Border.all(color: Colors.orange.shade600, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text('?',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: swatchText.withValues(alpha: 0.45),
                    height: 1.0)),
          ),
          const SizedBox(width: 8),
          // Code + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
                Text(t.name,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Proposed swatch (with symbol)
          SizedBox(
            width: 80,
            child: proposed.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward,
                          size: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: Colors.grey.shade400, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(proposed,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: swatchText,
                                height: 1.0)),
                      ),
                    ],
                  )
                : Text('none available',
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
          ),
        ],
      ),
    );
  }
}

// ─── Internal ────────────────────────────────────────────────────────────────

enum _ExportChoice {
  pdf(null),
  oxs(CrossStitchFormat.oxs),
  ;

  const _ExportChoice(this.format);
  final CrossStitchFormat? format;
}

class _ExportPickerDialog extends StatefulWidget {
  const _ExportPickerDialog();

  @override
  State<_ExportPickerDialog> createState() => _ExportPickerDialogState();
}

class _ExportPickerDialogState extends State<_ExportPickerDialog> {
  _ExportChoice _selected = _ExportChoice.pdf;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Pattern As…'),
      content: RadioGroup<_ExportChoice>(
        groupValue: _selected,
        onChanged: (v) => setState(() => _selected = v!),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FormatTile(
              value: _ExportChoice.pdf,
              label: 'PDF Pattern Chart',
              subtitle: 'Printable chart with legend',
              icon: Icons.picture_as_pdf_outlined,
            ),
            const Divider(height: 1),
            _FormatTile(
              value: _ExportChoice.oxs,
              label: 'Open Cross Stitch (.oxs)',
              subtitle: 'WinStitch / MacStitch compatible',
              icon: Icons.swap_horiz,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Export'),
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  final _ExportChoice value;
  final String label;
  final String subtitle;
  final IconData icon;

  const _FormatTile({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<_ExportChoice>(
      value: value,
      title: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
      subtitle: Text(subtitle),
    );
  }
}
