import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/pattern.dart';
import '../services/format_service.dart';
import '../services/pdf_service.dart';
import '../utils/snackbars.dart';

/// Shows a format-picker dialog then exports the pattern.
/// Returns true if the export succeeded.
Future<bool> showExportDialog(
    BuildContext context, CrossStitchPattern pattern,
    {bool useDmc = true}) async {
  final choice = await showDialog<_ExportChoice>(
    context: context,
    builder: (_) => const _ExportPickerDialog(),
  );
  if (choice == null || !context.mounted) return false;

  try {
    if (choice == _ExportChoice.pdf) {
      await PdfService.exportPattern(pattern, useDmc: useDmc);
      return true;
    }

    // For cross-stitch formats, ask the user for a save path.
    final format = choice.format!;
    final suggested =
        pattern.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final path = await FilePicker.platform.saveFile(
      fileName: '$suggested.${format.extension}',
      type: FileType.custom,
      allowedExtensions: [format.extension],
    );
    if (path == null) return false;

    final finalPath =
        path.endsWith('.${format.extension}') ? path : '$path.${format.extension}';
    await FormatService.exportFile(pattern, finalPath, format);

    if (context.mounted) {
      showSuccess(context,
          'Exported as ${finalPath.split(Platform.pathSeparator).last}');
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'Export failed: $e');
    return false;
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
