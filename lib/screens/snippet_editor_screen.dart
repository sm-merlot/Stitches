import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/layer/layer.dart';
import '../models/layer/layer_item.dart';
import '../models/pattern.dart';
import '../models/snippet/snippet.dart';
import '../models/snippet/snippet_palette.dart';
import '../models/thread.dart';
import '../data/dmc_colors.dart';
import '../providers/editor/editor_provider.dart';
import '../services/sprite_importer.dart';
import '../widgets/dialogs/dmc_picker_dialog.dart';
import '../widgets/sidebar/right_sidebar.dart';
import '../widgets/views/snippet_edit_view.dart';
import '../widgets/snippets/snippet_thumbnail.dart';

part 'snippet_editor_screen_dialogs.dart';

/// Preset canvas sizes shown in the size picker for new snippets.
const _presetSizes = [
  (label: '8×8',   w: 8,  h: 8),
  (label: '16×16', w: 16, h: 16),
  (label: '32×32', w: 32, h: 32),
  (label: '64×64', w: 64, h: 64),
];

/// Full-screen editor for creating or editing a [Snippet].
///
/// Pass [snippet] to edit an existing one; pass null to create a new one.
/// Pass [siblingSnippets] to allow importing other snippets as paste content.
/// On save, pops with the resulting [Snippet].
class SnippetEditorScreen extends StatelessWidget {
  final Snippet? snippet;
  final List<Snippet> siblingSnippets;
  final bool initialBlockMode;
  final Color aidaColor;

  const SnippetEditorScreen({
    super.key,
    this.snippet,
    this.siblingSnippets = const [],
    this.initialBlockMode = false,
    this.aidaColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    // Override editorProvider with a fresh scope so the reused
    // AidaWidget and EditorToolbar operate on the snippet canvas.
    return ProviderScope(
      overrides: [editorProvider.overrideWith(EditorNotifier.new)],
      child: _SnippetEditorBody(
        snippet: snippet,
        siblingSnippets: siblingSnippets,
        initialBlockMode: initialBlockMode,
        aidaColor: aidaColor,
      ),
    );
  }
}

class _SnippetEditorBody extends ConsumerStatefulWidget {
  final Snippet? snippet;
  final List<Snippet> siblingSnippets;
  final bool initialBlockMode;
  final Color aidaColor;
  const _SnippetEditorBody({
    required this.snippet,
    required this.siblingSnippets,
    required this.initialBlockMode,
    required this.aidaColor,
  });

  @override
  ConsumerState<_SnippetEditorBody> createState() => _SnippetEditorBodyState();
}

class _SnippetEditorBodyState extends ConsumerState<_SnippetEditorBody> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  // null = custom size chosen via dialog
  int? _selectedPresetIndex = 1; // default 16×16
  int _canvasW = 16;
  int _canvasH = 16;
  // Dirty-state proxy: fingerprints captured at load time (D3).
  int _initialStitchHash = 0;
  int _initialThreadHash = 0;
  List<SnippetPalette> _initialPalettes = const [];

  /// Max width of the title area (display + editor). Beyond this the static
  /// label ellipsises; the inline editor scrolls.
  static const double _kTitleMaxWidth = 280;

  @override
  void initState() {
    super.initState();
    final s = widget.snippet;
    _nameController = TextEditingController(text: s?.name ?? 'New snippet');
    // Rebuild on name changes so the title field can shrink/grow to fit the
    // text and the block-mode button sits flush against it.
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    _nameFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s != null) {
        // Editing existing snippet — load its data as a pattern.
        ref.read(editorProvider.notifier).loadPattern(
          CrossStitchPattern(
            name: s.name,
            width: s.width,
            height: s.height,
            threads: {for (final t in s.threads) t.dmcCode: t},
            aidaColor: widget.aidaColor,
            layerItems: [
              LayerLeaf(
                layer: Layer(
                  id: const Uuid().v4(),
                  name: 'Layer 1',
                  visible: true,
                  opacity: 1.0,
                  stitches: s.stitches,
                ),
              ),
            ],
          ),
          filePath: null,
        );
      } else {
        // New snippet — load empty pattern at selected size.
        _loadEmptyPattern();
      }
      // Snippet editor is always in edit mode — loadPattern defaults to
      // AppMode.view, which hides the toolbar and swaps the sidebar to the
      // Colours-only stitch layout. Flip to edit so the toolbar and the
      // Palettes/Colours tabs render.
      ref.read(editorProvider.notifier).setMode(AppMode.edit);
      if (widget.initialBlockMode) {
        ref.read(editorProvider.notifier).toggleColourMode();
      }
      // Initialise local palette state for this snippet editor session.
      //
      // loadPattern runs _assignSymbols, so state.pattern.threads now carry
      // their symbols — but s.palettes[0].threads are the raw pre-symbol
      // threads from the file. The Colours panel reads palette threads, so
      // we rebuild palette[0] from the symbolised pattern threads and let
      // initSnippetPalettesLocal propagate those symbols to every secondary
      // palette by slot (symbol belongs to the slot, not the thread).
      final editorNotifier = ref.read(editorProvider.notifier);
      if (s != null) {
        final symbolised = ref.read(editorProvider).pattern.threads.values.toList();
        final palettes = s.palettes.isNotEmpty
            ? [
                s.palettes[0].copyWith(threads: symbolised),
                ...s.palettes.skip(1),
              ]
            : [SnippetPalette.create(name: 'Palette 1', threads: symbolised)];
        editorNotifier.initSnippetPalettesLocal(
          palettes,
          s.activePaletteIndex,
          sourcePalette: s.sourcePalette,
        );
      } else {
        editorNotifier.initSnippetPalettesLocal(
            [SnippetPalette.create(name: 'Palette 1')], 0);
      }
      // Capture initial fingerprints for dirty-state detection (D3).
      // Run after a microtask so the state has settled.
      Future.microtask(() {
        if (mounted) {
          final s = ref.read(editorProvider);
          setState(() {
            _initialStitchHash =
                s.pattern.stitches.fold(0, (h, st) => Object.hash(h, st));
            _initialThreadHash = s.pattern.threads.values.fold(
                0, (h, t) => Object.hash(h, t.dmcCode, t.color.toARGB32(), t.symbol));
            _initialPalettes = s.snippetEditorState.palettes;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _loadEmptyPattern() {
    final notifier = ref.read(editorProvider.notifier);
    notifier.loadPattern(
      CrossStitchPattern.empty(
        name: _nameController.text,
        width: _canvasW,
        height: _canvasH,
      ).copyWith(aidaColor: widget.aidaColor),
    );
    // loadPattern resets mode to AppMode.view; restore edit mode so the
    // toolbar stays visible when the user changes the canvas size.
    notifier.setMode(AppMode.edit);
    // Re-initialise local palette state for the fresh canvas.
    notifier.initSnippetPalettesLocal(
        [SnippetPalette.create(name: 'Palette 1')], 0);
    // Reset dirty fingerprints so the new canvas starts clean.
    final s = ref.read(editorProvider);
    _initialStitchHash =
        s.pattern.stitches.fold(0, (h, st) => Object.hash(h, st));
    _initialThreadHash = s.pattern.threads.values.fold(
        0, (h, t) => Object.hash(h, t.dmcCode, t.color.toARGB32(), t.symbol));
    _initialPalettes = s.snippetEditorState.palettes;
  }

  void _onPresetSelected(int? index) {
    if (index == null) {
      // Custom — show dialog
      _showCustomSizeDialog();
      return;
    }
    final preset = _presetSizes[index];
    setState(() {
      _selectedPresetIndex = index;
      _canvasW = preset.w;
      _canvasH = preset.h;
    });
    _loadEmptyPattern();
  }

  Future<void> _showCustomSizeDialog() async {
    final wCtrl = TextEditingController(text: _canvasW.toString());
    final hCtrl = TextEditingController(text: _canvasH.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom size'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: wCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Width'),
                autofocus: true,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('×'),
            ),
            Expanded(
              child: TextField(
                controller: hCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    wCtrl.dispose();
    hCtrl.dispose();

    if (confirmed != true || !mounted) return;

    final w = int.tryParse(wCtrl.text) ?? _canvasW;
    final h = int.tryParse(hCtrl.text) ?? _canvasH;
    if (w < 1 || h < 1) return;

    setState(() {
      _selectedPresetIndex = null; // custom
      _canvasW = w;
      _canvasH = h;
    });
    _loadEmptyPattern();
  }

  Future<void> _showResizeDialog(BuildContext context) async {
    final pattern = ref.read(editorProvider).pattern;
    final result = await showDialog<(int, int, SnippetResizeMode)>(
      context: context,
      builder: (_) => _ResizeSnippetEditorDialog(
        currentWidth: pattern.width,
        currentHeight: pattern.height,
      ),
    );
    if (result != null) {
      ref
          .read(editorProvider.notifier)
          .resizeEditorPatternAsSnippet(result.$1, result.$2, result.$3);
    }
  }

  void _loadSnippetIntoClipboard(Snippet other) {
    ref.read(editorProvider.notifier).loadSnippetToClipboard(other);
  }

  void _showSnippetPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _SnippetPickerSheet(
        snippets: widget.siblingSnippets,
        onPick: (s) {
          Navigator.of(ctx).pop();
          _loadSnippetIntoClipboard(s);
        },
      ),
    );
  }

  void _save(BuildContext context) {
    final editorState = ref.read(editorProvider);
    final pattern = editorState.pattern;
    final name = _nameController.text.trim();

    final localPalettes = editorState.snippetEditorState.palettes;
    final activePaletteIdx = editorState.snippetEditorState.activePaletteIndex;

    // Preserve all primary palette threads without pruning unused ones.
    // Pruning can shorten the primary palette list, which shifts secondary
    // palette slot indices and corrupts the colour mapping on reload.
    final savedPalettes = localPalettes.isNotEmpty
        ? [
            localPalettes[0].copyWith(threads: pattern.threads.values.toList()),
            ...localPalettes.skip(1),
          ]
        : [SnippetPalette.create(name: 'Palette 1', threads: pattern.threads.values.toList())];

    final result = widget.snippet != null
        ? widget.snippet!.copyWith(
            name: name,
            width: pattern.width,
            height: pattern.height,
            palettes: savedPalettes,
            activePaletteIndex: activePaletteIdx.clamp(0, savedPalettes.length - 1),
            stitches: pattern.stitches,
          )
        : Snippet.create(
            name: name,
            width: pattern.width,
            height: pattern.height,
            threads: pattern.threads.values.toList(),
            stitches: pattern.stitches,
          );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.snippet == null;
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_isDirty()) {
          if (context.mounted) Navigator.of(context).pop();
          return;
        }
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text('Save your changes before closing?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('discard'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('save'),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (result == 'save') {
          _save(context);
        } else if (result == 'discard') {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed-width dirty indicator slot — always present so the
            // title/block-mode row doesn't shift when the dot appears.
            SizedBox(
              width: 8,
              height: 8,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _isDirty() ? 1.0 : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _buildTitle(theme),
            const SizedBox(width: 4),
            // ── Realistic mode toggle — title area, matches main editor ──
            IconButton(
              tooltip: state.editSession.colourMode ? 'Colour mode: on' : 'Colour mode: off',
              isSelected: state.editSession.colourMode,
              icon: const Icon(Icons.invert_colors_outlined),
              selectedIcon: const Icon(Icons.invert_colors),
              onPressed: () => notifier.toggleColourMode(),
              style: state.editSession.colourMode
                  ? IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                    )
                  : null,
            ),
          ],
        ),
        actions: [
          if (isNew) ...[
            const SizedBox(width: 8),
            _SizePicker(
              selectedPresetIndex: _selectedPresetIndex,
              customLabel: '$_canvasW×$_canvasH',
              onChanged: _onPresetSelected,
            ),
            const SizedBox(width: 8),
          ],
          if (!isNew)
            IconButton(
              tooltip: 'Resize snippet',
              icon: const Icon(Icons.aspect_ratio),
              onPressed: () => _showResizeDialog(context),
            ),
          TextButton(
            onPressed: _isDirty() ? () => _save(context) : null,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SnippetEditView(
                onPasteFromSnippet: widget.siblingSnippets.isNotEmpty
                    ? () => _showSnippetPicker(context)
                    : null,
              ),
            ),
            const RightSidebar(
                sidebarContext: RightSidebarContext.snippetEditor),
          ],
        ),
      ),
    );
  }

  /// Borderless, always-editable title field. Sized to fit the current text
  /// with a cap of [_kTitleMaxWidth] so the block-mode button stays flush to
  /// the name. When the text exceeds the cap the caret scrolls horizontally
  /// — same affordance as a plain AppBar [Text], but editable in place.
  Widget _buildTitle(ThemeData theme) {
    final style = theme.textTheme.titleMedium;
    final text =
        _nameController.text.isEmpty ? 'Snippet name' : _nameController.text;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = (tp.width + 12).clamp(60.0, _kTitleMaxWidth);
    return SizedBox(
      width: width,
      child: TextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        decoration: const InputDecoration(
          hintText: 'Snippet name',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: style,
        onSubmitted: (_) => _nameFocusNode.unfocus(),
      ),
    );
  }

  bool _isDirty() {
    final s = ref.read(editorProvider);
    // Stitch position changes
    final stitchHash =
        s.pattern.stitches.fold(0, (h, st) => Object.hash(h, st));
    if (stitchHash != _initialStitchHash) return true;
    // Thread list changes (colour/DMC replacements via replaceThread)
    final threadHash = s.pattern.threads.values.fold(
        0, (h, t) => Object.hash(h, t.dmcCode, t.color.toARGB32(), t.symbol));
    if (threadHash != _initialThreadHash) return true;
    // Palette changes (secondary colorway edits via setSnippetPaletteThreadColor)
    if (!identical(s.snippetEditorState.palettes, _initialPalettes)) return true;
    // Name changes (existing snippets only — new snippets with only a name
    // change and no stitches aren't worth warning about)
    if (widget.snippet != null &&
        _nameController.text.trim() != widget.snippet!.name) {
      return true;
    }
    return false;
  }
}
