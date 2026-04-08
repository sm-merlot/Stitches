import 'package:flutter/material.dart';

import '../../data/dmc_colors.dart';
import '../../models/thread.dart';

/// A modal dialog that lets the user search and pick a DMC colour, returning
/// a [Thread] for the chosen colour (or null if cancelled).
class DmcPickerDialog extends StatefulWidget {
  final Thread initialThread;
  const DmcPickerDialog({super.key, required this.initialThread});

  @override
  State<DmcPickerDialog> createState() => _DmcPickerDialogState();
}

class _DmcPickerDialogState extends State<DmcPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DmcColor> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return dmcColors;
    return dmcColors
        .where((c) =>
            c.code.toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return AlertDialog(
      title: const Text('Pick DMC colour'),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by code or name…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final c = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    title: Text('DMC ${c.code}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle:
                        Text(c.name, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.of(context).pop(
                      Thread(
                          dmcCode: c.code, color: c.color, name: c.name),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
