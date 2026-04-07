import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The format the user wants to produce.
enum ShareFormat { stitchesFile, oxs, pdf, png }

/// Show a format picker and return the chosen [ShareFormat], or null if
/// the user dismissed.
///
/// Presents a bottom sheet on mobile, a dialog on desktop — the same widget
/// is used by both the Share button and the Export flow.
///
/// [title] overrides the default "Share as…" / "Save As…" heading.
Future<ShareFormat?> showShareFormatPicker(
  BuildContext context, {
  String? title,
}) {
  final isMobile =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (isMobile) {
    return showModalBottomSheet<ShareFormat>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ShareFormatSheet(title: title),
    );
  }
  return showDialog<ShareFormat>(
    context: context,
    builder: (_) => _ShareFormatDialog(title: title),
  );
}

// ── Shared tile widget ────────────────────────────────────────────────────────

class _FormatOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ShareFormat value;

  const _FormatOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

// ── Bottom sheet (mobile) ─────────────────────────────────────────────────────

class _ShareFormatSheet extends StatelessWidget {
  final String? title;
  const _ShareFormatSheet({this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title ?? 'Share as…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _FormatOption(
            icon: Icons.grid_on_outlined,
            title: 'Pattern file',
            subtitle: '.stitches — open in StitchX',
            value: ShareFormat.stitchesFile,
          ),
          _FormatOption(
            icon: Icons.swap_horiz,
            title: 'Open Cross Stitch (.oxs)',
            subtitle: 'WinStitch / MacStitch compatible',
            value: ShareFormat.oxs,
          ),
          _FormatOption(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            subtitle: 'Printable chart with colour table',
            value: ShareFormat.pdf,
          ),
          _FormatOption(
            icon: Icons.image_outlined,
            title: 'PNG overview',
            subtitle: 'Realistic line-art preview image',
            value: ShareFormat.png,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Dialog (desktop) ──────────────────────────────────────────────────────────

class _ShareFormatDialog extends StatelessWidget {
  final String? title;
  const _ShareFormatDialog({this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title ?? 'Save As…'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FormatOption(
              icon: Icons.grid_on_outlined,
              title: 'Pattern file (.stitches)',
              subtitle: 'Open in StitchX',
              value: ShareFormat.stitchesFile,
            ),
            _FormatOption(
              icon: Icons.swap_horiz,
              title: 'Open Cross Stitch (.oxs)',
              subtitle: 'WinStitch / MacStitch compatible',
              value: ShareFormat.oxs,
            ),
            _FormatOption(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: 'Printable chart with colour table',
              value: ShareFormat.pdf,
            ),
            _FormatOption(
              icon: Icons.image_outlined,
              title: 'PNG overview',
              subtitle: 'Realistic line-art preview image',
              value: ShareFormat.png,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
