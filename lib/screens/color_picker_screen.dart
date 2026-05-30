import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../services/color_space.dart';
import '../services/sprite_importer.dart';

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
    // Capture the container before pushing so the new route inherits the
    // caller's ProviderScope (critical when opened from the snippet editor,
    // which runs its own scoped editorProvider).
    final container = ProviderScope.containerOf(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: screen,
        ),
      ),
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
  bool _showSimilar = false;

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

  /// Returns the DMC colour that is used as the "current" reference for the
  /// similar-colours panel.  In replace mode this is the thread being replaced;
  /// in select mode it is the currently active thread (if any).
  DmcColor? _referenceColor(EditorState editorState) {
    if (widget.replacingThreadId != null) {
      return dmcColorByCode(widget.replacingThreadId!);
    }
    final code = editorState.selectedThread?.dmcCode;
    if (code == null) return null;
    return dmcColorByCode(code);
  }

  /// Returns up to 24 DMC colours perceptually nearest to [ref], sorted by
  /// CIE Lab lightness (L*) ascending so the palette reads dark → light.
  List<DmcColor> _similarColors(DmcColor ref) {
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

  Widget _buildSimilarGrid(
    DmcColor ref,
    List<DmcColor> similar,
    bool useDmc,
    Set<String> usedCodes,
    EditorState editorState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reference colour header.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: ref.color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Similar to ${useDmc ? ref.code : (ref.anchorCode ?? ref.code)} · ${ref.name}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // Grid.
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: similar.length,
            itemBuilder: (context, index) {
              final c = similar[index];
              final isRef = c.code == ref.code;
              final isInPattern = usedCodes.contains(c.code);
              final isSelected =
                  editorState.selectedThread?.dmcCode == c.code;
              final displayCode =
                  useDmc ? c.code : (c.anchorCode ?? c.code);

              final borderColor = isRef
                  ? colorScheme.primary
                  : isSelected
                      ? colorScheme.primary.withValues(alpha: 0.7)
                      : Colors.grey.shade400;
              final borderWidth = isRef || isSelected ? 2.5 : 1.0;

              return Tooltip(
                message: c.name,
                child: GestureDetector(
                  onTap: () => _selectColor(c),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: c.color,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: borderColor,
                                  width: borderWidth,
                                ),
                              ),
                            ),
                            if (isRef)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Icon(
                                  Icons.radio_button_checked,
                                  size: 14,
                                  color: _contrastColor(c.color),
                                ),
                              ),
                            if (isInPattern && !isRef)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: _contrastColor(c.color),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayCode,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
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

  /// Returns white or black depending on which has better contrast with [bg].
  Color _contrastColor(Color bg) {
    final l = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
    return l > 0.4 ? Colors.black54 : Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final editorState = ref.watch(editorProvider);
    final usedCodes =
        editorState.pattern.threads.keys.toSet();
    final filtered = _filteredFor(settings.useDmc);
    final refColor = _referenceColor(editorState);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.replacingThreadId != null
            ? 'Replace Colour'
            : 'Select Colour'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(refColor != null ? 104 : 56),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
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
              if (refColor != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('See similar colours'),
                        selected: _showSimilar,
                        onSelected: (v) => setState(() {
                          _showSimilar = v;
                          if (v) {
                            _searchController.clear();
                            _searchQuery = '';
                          }
                        }),
                        avatar: const Icon(Icons.palette_outlined, size: 16),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _showSimilar && refColor != null
          ? _buildSimilarGrid(
              refColor,
              _similarColors(refColor),
              settings.useDmc,
              usedCodes,
              editorState,
            )
          : filtered.isEmpty
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
