import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The format the user wants to produce.
enum ShareFormat { stitchesFile, oxs, pdf, png }

/// Result from the share/export picker: chosen format + data-stripping options.
/// [stripProgress] and [stripPageSettings] only apply to [ShareFormat.stitchesFile].
class PatternShareResult {
  final ShareFormat format;
  /// If true, remove progress data from the exported .stitches file.
  final bool stripProgress;
  /// If true, remove page settings from the exported .stitches file.
  final bool stripPageSettings;

  const PatternShareResult({
    required this.format,
    this.stripProgress = false,
    this.stripPageSettings = false,
  });
}

/// Show a format picker and return a [PatternShareResult], or null if dismissed.
///
/// [hasProgress] and [hasPageSettings] control whether strip-data checkboxes
/// appear (only when format is .stitches and the pattern has that data).
///
/// Presents a bottom sheet on mobile, a dialog on desktop.
Future<PatternShareResult?> showShareFormatPicker(
  BuildContext context, {
  String? title,
  bool hasProgress = false,
  bool hasPageSettings = false,
}) {
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (isMobile) {
    return showModalBottomSheet<PatternShareResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ShareFormatSheet(
        title: title,
        hasProgress: hasProgress,
        hasPageSettings: hasPageSettings,
      ),
    );
  }
  return showDialog<PatternShareResult>(
    context: context,
    builder: (_) => _ShareFormatDialog(
      title: title,
      hasProgress: hasProgress,
      hasPageSettings: hasPageSettings,
    ),
  );
}

// ── Shared state logic ────────────────────────────────────────────────────────

String _formatLabel(ShareFormat f) => switch (f) {
      ShareFormat.stitchesFile => 'Pattern file (.stitches)',
      ShareFormat.oxs          => 'Open Cross Stitch (.oxs)',
      ShareFormat.pdf          => 'PDF',
      ShareFormat.png          => 'PNG overview',
    };

String _formatSubtitle(ShareFormat f) => switch (f) {
      ShareFormat.stitchesFile => 'Open in StitchX',
      ShareFormat.oxs          => 'WinStitch / MacStitch compatible',
      ShareFormat.pdf          => 'Printable chart with colour table',
      ShareFormat.png          => 'Realistic line-art preview image',
    };

// ── Bottom sheet (mobile) ─────────────────────────────────────────────────────

class _ShareFormatSheet extends StatefulWidget {
  final String? title;
  final bool hasProgress;
  final bool hasPageSettings;

  const _ShareFormatSheet({
    this.title,
    required this.hasProgress,
    required this.hasPageSettings,
  });

  @override
  State<_ShareFormatSheet> createState() => _ShareFormatSheetState();
}

class _ShareFormatSheetState extends State<_ShareFormatSheet> {
  ShareFormat _format = ShareFormat.stitchesFile;
  bool _stripProgress = true;
  bool _stripPageSettings = false;

  void _confirm() {
    Navigator.of(context).pop(PatternShareResult(
      format: _format,
      stripProgress: _stripProgress,
      stripPageSettings: _stripPageSettings,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showOptions = _format == ShareFormat.stitchesFile &&
        (widget.hasProgress || widget.hasPageSettings);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title ?? 'Share as…',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ShareFormat>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Format',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: ShareFormat.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(_formatLabel(f))))
                  .toList(),
              onChanged: (f) => setState(() => _format = f!),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _formatSubtitle(_format),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (showOptions) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              _DataOptionsSection(
                hasProgress: widget.hasProgress,
                hasPageSettings: widget.hasPageSettings,
                stripProgress: _stripProgress,
                stripPageSettings: _stripPageSettings,
                onProgressChanged: (v) => setState(() => _stripProgress = v),
                onPageSettingsChanged: (v) => setState(() => _stripPageSettings = v),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _confirm,
              child: Text(widget.title != null ? 'Export' : 'Share'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ── Dialog (desktop) ──────────────────────────────────────────────────────────

class _ShareFormatDialog extends StatefulWidget {
  final String? title;
  final bool hasProgress;
  final bool hasPageSettings;

  const _ShareFormatDialog({
    this.title,
    required this.hasProgress,
    required this.hasPageSettings,
  });

  @override
  State<_ShareFormatDialog> createState() => _ShareFormatDialogState();
}

class _ShareFormatDialogState extends State<_ShareFormatDialog> {
  ShareFormat _format = ShareFormat.stitchesFile;
  bool _stripProgress = true;
  bool _stripPageSettings = false;

  void _confirm() {
    Navigator.of(context).pop(PatternShareResult(
      format: _format,
      stripProgress: _stripProgress,
      stripPageSettings: _stripPageSettings,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showOptions = _format == ShareFormat.stitchesFile &&
        (widget.hasProgress || widget.hasPageSettings);

    return AlertDialog(
      title: Text(widget.title ?? 'Share as…'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ShareFormat>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Format',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: ShareFormat.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(_formatLabel(f))))
                  .toList(),
              onChanged: (f) => setState(() => _format = f!),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _formatSubtitle(_format),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (showOptions) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              _DataOptionsSection(
                hasProgress: widget.hasProgress,
                hasPageSettings: widget.hasPageSettings,
                stripProgress: _stripProgress,
                stripPageSettings: _stripPageSettings,
                onProgressChanged: (v) => setState(() => _stripProgress = v),
                onPageSettingsChanged: (v) => setState(() => _stripPageSettings = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(widget.title != null ? 'Export' : 'Share'),
        ),
      ],
    );
  }
}

// ── Shared data-options section ───────────────────────────────────────────────

class _DataOptionsSection extends StatelessWidget {
  final bool hasProgress;
  final bool hasPageSettings;
  final bool stripProgress;
  final bool stripPageSettings;
  final ValueChanged<bool> onProgressChanged;
  final ValueChanged<bool> onPageSettingsChanged;

  const _DataOptionsSection({
    required this.hasProgress,
    required this.hasPageSettings,
    required this.stripProgress,
    required this.stripPageSettings,
    required this.onProgressChanged,
    required this.onPageSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
          child: Text(
            'Include in .stitches file',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (hasPageSettings)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Page settings'),
            subtitle: const Text('Print page layout'),
            value: !stripPageSettings,
            onChanged: (v) => onPageSettingsChanged(!(v ?? false)),
          ),
        if (hasProgress)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Progress data'),
            subtitle: const Text('Stitches marked as done'),
            value: !stripProgress,
            onChanged: (v) => onProgressChanged(!(v ?? true)),
          ),
      ],
    );
  }
}
