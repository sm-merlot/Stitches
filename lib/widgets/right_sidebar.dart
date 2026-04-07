import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/editor/editor_provider.dart';
import 'layers_panel.dart';
import 'right_sidebar_colours_panel.dart';
import 'right_sidebar_palettes_panel.dart';

enum RightSidebarContext { mainEditor, snippetEditor }

const _kCollapsedKey = 'sidebar_right_collapsed';
const _kCollapsedWidth = 32.0;
const _kDefaultWidth = 240.0;
const _kMinWidth = 140.0;
const _kMaxWidth = 350.0;

class RightSidebar extends ConsumerStatefulWidget {
  final RightSidebarContext sidebarContext;

  /// When non-null, overrides local collapsed state (used by WorkspaceScreen
  /// on phones to coordinate with the folder sidebar).
  final bool? collapsedOverride;

  /// Called when the user toggles collapsed state while [collapsedOverride] is
  /// in use. The caller is responsible for updating [collapsedOverride].
  final ValueChanged<bool>? onCollapsedChanged;

  const RightSidebar({
    super.key,
    required this.sidebarContext,
    this.collapsedOverride,
    this.onCollapsedChanged,
  });

  @override
  ConsumerState<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends ConsumerState<RightSidebar> {
  bool _collapsed = false;
  double _width = _kDefaultWidth;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _collapsed = prefs.getBool(_kCollapsedKey) ?? false);
    }
  }

  Future<void> _setCollapsed(bool value) async {
    if (widget.onCollapsedChanged != null) {
      widget.onCollapsedChanged!(value);
      return;
    }
    setState(() => _collapsed = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCollapsedKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final theme = Theme.of(context);
    final isSnippet = widget.sidebarContext == RightSidebarContext.snippetEditor;

    if (!state.isFileOpen && !isSnippet) return const SizedBox.shrink();

    final collapsed = widget.collapsedOverride ?? _collapsed;
    if (collapsed) {
      return _buildCollapsedStrip(theme);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Resize handle (5px transparent hit-target with a thin divider line)
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _width =
                    (_width - details.delta.dx).clamp(_kMinWidth, _kMaxWidth);
              });
            },
            child: Container(
              width: 5,
              color: Colors.transparent,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor,
              ),
            ),
          ),
        ),
        // Panel content
        SizedBox(
          width: _width,
          child: Container(
            color: theme.colorScheme.surface,
            child: state.mode != AppMode.edit
                ? _buildStitchLayout(theme)
                : DefaultTabController(
                    length: 2,
                    child: _buildTabbedLayout(theme, isSnippet),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedStrip(ThemeData theme) {
    final isTouch = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    return Container(
      width: _kCollapsedWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          IconButton(
            tooltip: 'Expand sidebar',
            icon: Icon(Icons.chevron_left, size: isTouch ? 22 : 18),
            padding: isTouch ? const EdgeInsets.all(6) : EdgeInsets.zero,
            visualDensity: isTouch ? VisualDensity.standard : VisualDensity.compact,
            onPressed: () => _setCollapsed(false),
          ),
        ],
      ),
    );
  }

  /// Stitch mode: no tabs — just the Colours panel with a simple header.
  Widget _buildStitchLayout(ThemeData theme) {
    final isTouch = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final editorState = ref.watch(editorProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            children: [
              Text('Colours',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Collapse sidebar',
                icon: Icon(Icons.chevron_right, size: isTouch ? 22 : 18),
                padding: isTouch ? const EdgeInsets.all(6) : EdgeInsets.zero,
                visualDensity: isTouch ? VisualDensity.standard : VisualDensity.compact,
                onPressed: () => _setCollapsed(true),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: ColoursPanel(mode: ColoursPanelMode.stitch)),
        if (editorState.mode == AppMode.stitch) ...[
          const Divider(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MarkDoneButton(state: editorState)),
              Expanded(child: StitchDemoButton(state: editorState)),
            ],
          ),
        ],
      ],
    );
  }

  /// Design mode (main editor or snippet editor): two tabs sharing one controller.
  /// [DefaultTabController] is already an ancestor in [build].
  Widget _buildTabbedLayout(ThemeData theme, bool isSnippet) {
    final isTouch = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  tabs: isSnippet
                      ? const [Tab(text: 'Palettes'), Tab(text: 'Colours')]
                      : const [Tab(text: 'Layers'), Tab(text: 'Colours')],
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  padding: EdgeInsets.zero,
                  indicatorSize: TabBarIndicatorSize.label,
                ),
              ),
              IconButton(
                tooltip: 'Collapse sidebar',
                icon: Icon(Icons.chevron_right, size: isTouch ? 22 : 18),
                padding: isTouch ? const EdgeInsets.all(6) : EdgeInsets.zero,
                visualDensity: isTouch ? VisualDensity.standard : VisualDensity.compact,
                onPressed: () => _setCollapsed(true),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            children: isSnippet
                ? const [
                    PalettesPanel(),
                    ColoursPanel(mode: ColoursPanelMode.snippet),
                  ]
                : const [
                    LayersPanelBody(),
                    ColoursPanel(mode: ColoursPanelMode.design),
                  ],
          ),
        ),
      ],
    );
  }
}
