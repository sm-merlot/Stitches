import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/dmc_colors.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart';
import '../providers/settings_provider.dart';

class ColorPickerScreen extends ConsumerStatefulWidget {
  const ColorPickerScreen({super.key});

  @override
  ConsumerState<ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends ConsumerState<ColorPickerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  static const _uuid = Uuid();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DmcColor> get _filtered {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return dmcColors;
    return dmcColors
        .where((c) =>
            c.code.toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q))
        .toList();
  }

  void _selectColor(DmcColor dmcColor) {
    final editorState = ref.read(editorProvider);
    final notifier = ref.read(editorProvider.notifier);

    // Check if this DMC code already exists in the pattern's thread list
    final existing = editorState.pattern.threads
        .where((t) => t.code == dmcColor.code)
        .firstOrNull;

    if (existing != null) {
      notifier.setSelectedThread(existing.id);
    } else {
      // Add this thread to the pattern
      final thread = Thread(
        id: _uuid.v4(),
        code: dmcColor.code,
        color: dmcColor.color,
        name: dmcColor.name,
      );
      notifier.addThread(thread);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final editorState = ref.watch(editorProvider);
    final usedCodes =
        editorState.pattern.threads.map((t) => t.code).toSet();
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.useDmc ? 'DMC Colours' : 'Anchor Colours'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by code or name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No colours found'))
          : ListView.builder(
              itemCount: filtered.length,
              itemExtent: 56,
              itemBuilder: (context, index) {
                final c = filtered[index];
                final isInPattern = usedCodes.contains(c.code);
                final isSelected =
                    editorState.selectedThread?.code == c.code;

                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                  ),
                  title: Text(
                    c.code,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(c.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isInPattern)
                        Tooltip(
                          message: 'Already in pattern',
                          child: Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.radio_button_checked,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  selected: isSelected,
                  onTap: () => _selectColor(c),
                );
              },
            ),
    );
  }
}
