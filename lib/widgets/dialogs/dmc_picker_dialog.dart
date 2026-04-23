import 'package:flutter/material.dart';

import '../../data/dmc_colors.dart';
import '../../models/thread.dart';
import '../../services/color_space.dart';
import '../../services/sprite_importer.dart';

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
  bool _showSimilar = false;

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

  /// 24 nearest DMC colours to [ref] sorted by Lab L* (dark → light).
  List<DmcColor> _similarColors(Thread ref) {
    final r = (ref.color.r * 255).round();
    final g = (ref.color.g * 255).round();
    final b = (ref.color.b * 255).round();
    final similar = SpriteImporter.nearestDmcColours(r, g, b, count: 24);
    similar.sort((a, b) {
      final la = rgbToLab(
        (a.color.r * 255).round(),
        (a.color.g * 255).round(),
        (a.color.b * 255).round(),
      ).$1;
      final lb = rgbToLab(
        (b.color.r * 255).round(),
        (b.color.g * 255).round(),
        (b.color.b * 255).round(),
      ).$1;
      return la.compareTo(lb);
    });
    return similar;
  }

  void _pick(DmcColor c) => Navigator.of(context).pop(
        Thread(dmcCode: c.code, color: c.color, name: c.name),
      );

  Color _contrastColor(Color bg) {
    final l = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
    return l > 0.4 ? Colors.black54 : Colors.white70;
  }

  Widget _buildSimilarGrid(List<DmcColor> similar) {
    final ref = widget.initialThread;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reference colour header.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: ref.color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Similar to DMC ${ref.dmcCode} · ${ref.name}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Grid.
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.78,
            ),
            itemCount: similar.length,
            itemBuilder: (context, index) {
              final c = similar[index];
              final isRef = c.code == ref.dmcCode;
              final borderColor =
                  isRef ? colorScheme.primary : Colors.black12;
              final borderWidth = isRef ? 2.5 : 1.0;

              return Tooltip(
                message: '${c.code} · ${c.name}',
                child: GestureDetector(
                  onTap: () => _pick(c),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: c.color,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: borderColor,
                                  width: borderWidth,
                                ),
                              ),
                            ),
                            if (isRef)
                              Positioned(
                                top: 3,
                                left: 3,
                                child: Icon(
                                  Icons.radio_button_checked,
                                  size: 12,
                                  color: _contrastColor(c.color),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.code,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final similar = _showSimilar ? _similarColors(widget.initialThread) : null;

    return AlertDialog(
      title: const Text('Pick DMC colour'),
      content: SizedBox(
        width: 320,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by code or name…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilterChip(
                  label: const Text('Similar colours'),
                  selected: _showSimilar,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() {
                    _showSimilar = v;
                    if (v) {
                      _searchCtrl.clear();
                      _query = '';
                    }
                  }),
                  avatar: const Icon(Icons.palette_outlined, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _showSimilar
                  ? _buildSimilarGrid(similar!)
                  : filtered.isEmpty
                      ? const Center(child: Text('No colours found'))
                      : ListView.builder(
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
                              subtitle: Text(c.name,
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () => _pick(c),
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
