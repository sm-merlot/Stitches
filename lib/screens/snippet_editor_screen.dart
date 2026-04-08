import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../models/pattern.dart';
import '../models/snippet.dart';
import '../models/snippet_palette.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../widgets/dialogs/dmc_picker_dialog.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/pattern_canvas.dart';
import '../widgets/right_sidebar.dart';
import '../widgets/snippet_thumbnail.dart';

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
    // PatternCanvas and EditorToolbar operate on the snippet canvas.
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
  // null = custom size chosen via dialog
  int? _selectedPresetIndex = 1; // default 16×16
  int _canvasW = 16;
  int _canvasH = 16;
  // Dirty-state proxy: stitch fingerprint at load time (D3).
  int _initialStitchHash = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.snippet;
    _nameController = TextEditingController(text: s?.name ?? 'New snippet');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s != null) {
        // Editing existing snippet — load its data as a pattern.
        ref.read(editorProvider.notifier).loadPattern(
          CrossStitchPattern(
            name: s.name,
            width: s.width,
            height: s.height,
            threads: s.threads,
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
      if (widget.initialBlockMode) {
        ref.read(editorProvider.notifier).toggleBlockMode();
      }
      // Initialise local palette state for this snippet editor session.
      final editorNotifier = ref.read(editorProvider.notifier);
      if (s != null) {
        editorNotifier.initSnippetPalettesLocal(s.palettes, s.activePaletteIndex);
      } else {
        editorNotifier.initSnippetPalettesLocal(
            [SnippetPalette.create(name: 'Palette 1')], 0);
      }
      // Capture initial stitch fingerprint for dirty-state detection (D3).
      // Run after a microtask so the state has settled.
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _initialStitchHash = ref
                .read(editorProvider)
                .pattern
                .stitches
                .fold(0, (h, s) => Object.hash(h, s));
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadEmptyPattern() {
    ref.read(editorProvider.notifier).loadPattern(
      CrossStitchPattern.empty(
        name: _nameController.text,
        width: _canvasW,
        height: _canvasH,
      ).copyWith(aidaColor: widget.aidaColor),
    );
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

  KeyEventResult _handleKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final notifier = ref.read(editorProvider.notifier);
    final state = ref.read(editorProvider);
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final key = event.logicalKey;

    if (meta || ctrl) {
      if (key == LogicalKeyboardKey.keyZ && !shift) {
        notifier.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyZ && shift) {
        notifier.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        notifier.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        notifier.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        notifier.copySelection();
        return KeyEventResult.handled;
      }
      if (!shift && key == LogicalKeyboardKey.keyV) {
        notifier.enterPasteMode();
        return KeyEventResult.handled;
      }
      if (shift && key == LogicalKeyboardKey.keyH) {
        if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
          notifier.flipSelectionH();
        } else if (state.drawingMode == DrawingMode.paste) {
          notifier.flipClipboardH();
        } else {
          notifier.flipCanvasH();
        }
        return KeyEventResult.handled;
      }
      if (shift && key == LogicalKeyboardKey.keyV) {
        if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
          notifier.flipSelectionV();
        } else if (state.drawingMode == DrawingMode.paste) {
          notifier.flipClipboardV();
        } else {
          notifier.flipCanvasV();
        }
        return KeyEventResult.handled;
      }
      if (shift && key == LogicalKeyboardKey.bracketRight) {
        if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
          notifier.rotateSelectionCW();
        } else if (state.drawingMode == DrawingMode.paste) {
          notifier.rotateClipboardCW();
        } else {
          notifier.rotateCanvasCW();
        }
        return KeyEventResult.handled;
      }
      if (shift && key == LogicalKeyboardKey.bracketLeft) {
        if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
          notifier.rotateSelectionCW(); notifier.rotateSelectionCW(); notifier.rotateSelectionCW();
        } else if (state.drawingMode == DrawingMode.paste) {
          notifier.rotateClipboardCW(); notifier.rotateClipboardCW(); notifier.rotateClipboardCW();
        } else {
          notifier.rotateCanvasCW(); notifier.rotateCanvasCW(); notifier.rotateCanvasCW();
        }
        return KeyEventResult.handled;
      }
    }

    switch (key) {
      case LogicalKeyboardKey.keyD:
        notifier.setDrawingMode(DrawingMode.draw);
      case LogicalKeyboardKey.keyE:
        notifier.setDrawingMode(DrawingMode.erase);
      case LogicalKeyboardKey.space:
        notifier.setDrawingMode(DrawingMode.pan);
      case LogicalKeyboardKey.keyS:
        notifier.setDrawingMode(DrawingMode.select);
      case LogicalKeyboardKey.keyC:
        notifier.setDrawingMode(DrawingMode.colorPicker);
      case LogicalKeyboardKey.digit1:
        notifier.setTool(DrawingTool.fullStitch);
      case LogicalKeyboardKey.digit2:
        notifier.setTool(DrawingTool.halfForward);
      case LogicalKeyboardKey.digit3:
        notifier.setTool(DrawingTool.halfBackward);
      case LogicalKeyboardKey.digit4:
        notifier.setTool(DrawingTool.halfCross);
      case LogicalKeyboardKey.digit5:
        notifier.setTool(DrawingTool.quarterDiag);
      case LogicalKeyboardKey.digit6:
        notifier.setTool(DrawingTool.quarterCross);
      case LogicalKeyboardKey.digit7:
        notifier.setTool(DrawingTool.backstitch);
      case LogicalKeyboardKey.digit8:
        notifier.setTool(DrawingTool.fill);
      case LogicalKeyboardKey.digit9:
        notifier.setDrawingMode(DrawingMode.erase);
        if (!state.fillEraseActive) notifier.toggleFillErase();
      case LogicalKeyboardKey.escape:
        notifier.cancelSelection();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        notifier.deleteSelection();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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

    final localPalettes = editorState.snippetPalettes;
    final activePaletteIdx = editorState.snippetActivePaletteIndex;

    // Preserve all primary palette threads without pruning unused ones.
    // Pruning can shorten the primary palette list, which shifts secondary
    // palette slot indices and corrupts the colour mapping on reload.
    final savedPalettes = localPalettes.isNotEmpty
        ? [
            localPalettes[0].copyWith(threads: pattern.threads),
            ...localPalettes.skip(1),
          ]
        : [SnippetPalette.create(name: 'Palette 1', threads: pattern.threads)];

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
            threads: pattern.threads,
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
        title: SizedBox(
          width: 200,
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Snippet name',
              border: InputBorder.none,
            ),
            style: theme.textTheme.titleMedium,
          ),
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
          IconButton(
            tooltip: state.blockMode ? 'Block mode: on' : 'Block mode: off',
            isSelected: state.blockMode,
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            onPressed: () => notifier.toggleBlockMode(),
            style: state.blockMode
                ? IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  )
                : null,
          ),
          TextButton(
            onPressed: () => _save(context),
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKeys,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  const Expanded(child: PatternCanvas()),
                  EditorToolbar(
                    showSnippetsButton: false,
                    showSaveAsSnippetButton: false,
                    showSpriteSheetButton: false,
                    showWholeCanvasTransforms: true,
                    showAidaButton: false,
                    onPasteFromSnippet: widget.siblingSnippets.isNotEmpty
                        ? () => _showSnippetPicker(context)
                        : null,
                  ),
                ],
              ),
            ),
            const RightSidebar(
                sidebarContext: RightSidebarContext.snippetEditor),
          ],
        ),
      ),
      ),
    );
  }

  bool _isDirty() {
    // Stitch changes
    final current = ref
        .read(editorProvider)
        .pattern
        .stitches
        .fold(0, (h, s) => Object.hash(h, s));
    if (current != _initialStitchHash) return true;
    // Name changes (existing snippets only — new snippets with only a name
    // change and no stitches aren't worth warning about)
    if (widget.snippet != null &&
        _nameController.text.trim() != widget.snippet!.name) { return true; }
    return false;
  }
}
