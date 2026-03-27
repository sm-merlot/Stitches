import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../providers/editor_provider.dart';
import '../providers/settings_provider.dart';

/// Opens the colour picker as a modal dialog on desktop, full-screen push on mobile.
///
/// If [replacingThreadId] is provided, selecting a colour calls
/// [EditorNotifier.replaceThread] instead of adding a new thread.
void showColorPicker(
  BuildContext context, {
  String? replacingThreadId,
}) {
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  final screen = ColorPickerScreen(replacingThreadId: replacingThreadId);

  if (isDesktop) {
    showDialog<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          clipBehavior: Clip.hardEdge,
          insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          child: SizedBox(width: 440, height: 600, child: screen),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class ColorPickerScreen extends ConsumerStatefulWidget {
  final String? replacingThreadId;

  const ColorPickerScreen({super.key, this.replacingThreadId});

  @override
  ConsumerState<ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends ConsumerState<ColorPickerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DmcColor> _filteredFor(bool useDmc) {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return dmcColors;
    return dmcColors
        .where((c) {
          final displayCode = (useDmc ? c.code : c.anchorCode) ?? c.code;
          return displayCode.toLowerCase().contains(q) ||
              c.name.toLowerCase().contains(q);
        })
        .toList();
  }

  void _selectColor(DmcColor dmcColor) {
    final notifier = ref.read(editorProvider.notifier);

    // Replace mode — remap all stitches to the new colour.
    if (widget.replacingThreadId != null) {
      final replacingId = widget.replacingThreadId!;
      notifier.replaceThread(
        replacingId,
        dmcColor.code,
        dmcColor.color,
        dmcColor.name,
      );
      Navigator.of(context).pop();
      return;
    }

    // Select mode — set as active colour; palette entry created on first stitch.
    notifier.setSelectedThread(dmcColor.code);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final editorState = ref.watch(editorProvider);
    final usedCodes =
        editorState.pattern.threads.map((t) => t.dmcCode).toSet();
    final filtered = _filteredFor(settings.useDmc);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.replacingThreadId != null
            ? 'Replace Colour'
            : 'Select Colour'),
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
                    editorState.selectedThread?.dmcCode == c.code;

                final displayCode = settings.useDmc
                    ? c.code
                    : (c.anchorCode ?? c.code);
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
                    displayCode,
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
