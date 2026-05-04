import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/page/page_config.dart';
import '../providers/editor/editor_provider.dart';

Future<void> showPageModeDialog(BuildContext context, WidgetRef ref) {
  return showDialog(
    context: context,
    builder: (_) => _PageModeDialog(initial: ref.read(editorProvider).pattern.pageConfig),
  ).then((config) {
    if (config != null && context.mounted) {
      ref.read(editorProvider.notifier).updatePageConfig(config as PageConfig);
    }
  });
}

class _PageModeDialog extends StatefulWidget {
  final PageConfig initial;
  const _PageModeDialog({required this.initial});

  @override
  State<_PageModeDialog> createState() => _PageModeDialogState();
}

class _PageModeDialogState extends State<_PageModeDialog> {
  late bool _enabled;
  late int _pageWidth;
  late int _pageHeight;
  late bool _fuzzyEdges;

  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _pageWidth = widget.initial.pageWidth;
    _pageHeight = widget.initial.pageHeight;
    _fuzzyEdges = widget.initial.tolerance > 0;
    _widthCtrl.text = '$_pageWidth';
    _heightCtrl.text = '$_pageHeight';
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Page Mode'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable page mode'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _widthCtrl,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      labelText: 'Page width',
                      suffixText: 'stitches',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) _pageWidth = n;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _heightCtrl,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      labelText: 'Page height',
                      suffixText: 'stitches',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) _pageHeight = n;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Text('Fuzzy edges'),
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        'Shifts page boundaries to follow colour edges,\n'
                        'keeping stitch objects whole where possible.\n'
                        'Off = straight page edges.',
                    child: Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              value: _fuzzyEdges,
              onChanged: _enabled
                  ? (v) => setState(() => _fuzzyEdges = v)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            PageConfig(
              enabled: _enabled,
              pageWidth: _pageWidth.clamp(1, 9999),
              pageHeight: _pageHeight.clamp(1, 9999),
              tolerance: _fuzzyEdges ? 5 : 0,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
