import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/snippet.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart';
import '../screens/snippet_editor_screen.dart';
import 'snippet_thumbnail.dart';

/// Modal bottom sheet that shows the current pattern's snippets.
///
/// Tap a snippet to load it into paste mode.
/// Long-press for rename / edit / delete options.
/// Tap the + button to create a new snippet.
class SnippetsPanel extends ConsumerWidget {
  const SnippetsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snippets = ref.watch(editorProvider.select((s) => s.pattern.snippets));
    final aidaColor = ref.watch(editorProvider.select((s) => s.pattern.aidaColor));
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Snippets', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New snippet',
                    onPressed: () => _openEditor(context, ref, null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: snippets.isEmpty
                  ? _EmptyState(onNew: () => _openEditor(context, ref, null))
                  : GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: snippets.length,
                      itemBuilder: (context, i) => _SnippetCard(
                        snippet: snippets[i],
                        aidaColor: aidaColor,
                        onTap: () =>
                            _loadSnippet(context, ref, snippets[i]),
                        onMenuTap: () =>
                            _showOptions(context, ref, snippets[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSnippet(BuildContext context, WidgetRef ref, Snippet snippet) async {
    final navigator = Navigator.of(context);
    await ref.read(editorProvider.notifier).loadSnippetToClipboard(snippet);
    navigator.pop();
  }

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, Snippet? snippet) async {
    // Capture both before popping — the widget will be unmounted after pop,
    // making ref and the original context unsafe to use.
    final notifier = ref.read(editorProvider.notifier);
    final navigator = Navigator.of(context);
    final allSnippets = ref.read(editorProvider.select((s) => s.pattern.snippets));
    final siblings = allSnippets.where((s) => s.id != snippet?.id).toList();

    navigator.pop(); // close the panel

    final result = await navigator.push<Snippet>(
      MaterialPageRoute(
        builder: (_) => SnippetEditorScreen(snippet: snippet, siblingSnippets: siblings),
        fullscreenDialog: true,
      ),
    );

    if (result == null) return;
    if (snippet == null) {
      notifier.addSnippet(result);
    } else {
      notifier.updateSnippet(result);
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref, Snippet snippet) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openEditor(context, ref, snippet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRename(context, ref, snippet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_with_outlined),
              title: const Text('Resize…'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showResize(context, ref, snippet);
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _TransformButton(
                    icon: Icons.flip,
                    label: 'Flip H',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref.read(editorProvider.notifier)
                          .transformSnippet(snippet.id, SnippetTransform.flipH);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TransformButton(
                    icon: Icons.flip,
                    label: 'Flip V',
                    iconFlip: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref.read(editorProvider.notifier)
                          .transformSnippet(snippet.id, SnippetTransform.flipV);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TransformButton(
                    icon: Icons.rotate_90_degrees_cw_outlined,
                    label: 'Rotate 90°',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref.read(editorProvider.notifier)
                          .transformSnippet(snippet.id, SnippetTransform.rotateCW);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(editorProvider.notifier).deleteSnippet(snippet.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRename(BuildContext context, WidgetRef ref, Snippet snippet) {
    final controller = TextEditingController(text: snippet.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename snippet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Leave empty for no name',
          ),
          onSubmitted: (_) => _commitRename(ctx, ref, snippet, controller.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  _commitRename(ctx, ref, snippet, controller.text),
              child: const Text('Rename')),
        ],
      ),
    );
  }

  void _commitRename(
      BuildContext context, WidgetRef ref, Snippet snippet, String name) {
    ref
        .read(editorProvider.notifier)
        .updateSnippet(snippet.copyWith(name: name.trim()));
    Navigator.of(context).pop();
  }

  void _showResize(BuildContext context, WidgetRef ref, Snippet snippet) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SnippetResizeDialog(
        snippet: snippet,
        onResize: (newW, newH, mode) {
          ref.read(editorProvider.notifier).resizeSnippet(snippet.id, newW, newH, mode);
        },
      ),
    );
  }
}

class _SnippetCard extends StatelessWidget {
  final Snippet snippet;
  final Color aidaColor;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;

  const _SnippetCard({
    required this.snippet,
    required this.aidaColor,
    required this.onTap,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = snippet.name.isNotEmpty;
    final label = hasName ? snippet.name : '${snippet.width}×${snippet.height}';
    final labelStyle = hasName
        ? theme.textTheme.labelSmall
        : theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onMenuTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SnippetThumbnail(
                    snippet: snippet,
                    aidaColor: aidaColor,
                    size: double.infinity,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: onMenuTap,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(1),
                      child: const Icon(Icons.more_vert,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (snippet.threads.isNotEmpty) ...[
            const SizedBox(height: 3),
            _SnippetPaletteDots(threads: snippet.threads),
          ],
        ],
      ),
    );
  }
}

class _SnippetResizeDialog extends StatefulWidget {
  final Snippet snippet;
  final void Function(int newW, int newH, SnippetResizeMode mode) onResize;

  const _SnippetResizeDialog({required this.snippet, required this.onResize});

  @override
  State<_SnippetResizeDialog> createState() => _SnippetResizeDialogState();
}

class _SnippetResizeDialogState extends State<_SnippetResizeDialog> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  SnippetResizeMode _mode = SnippetResizeMode.clip;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(text: widget.snippet.width.toString());
    _hCtrl = TextEditingController(text: widget.snippet.height.toString());
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final w = int.tryParse(_wCtrl.text.trim());
    final h = int.tryParse(_hCtrl.text.trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() => _error = 'Enter positive integers for width and height.');
      return;
    }
    Navigator.of(context).pop();
    widget.onResize(w, h, _mode);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resize snippet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current size: ${widget.snippet.width} × ${widget.snippet.height}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _wCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Width', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Height', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<SnippetResizeMode>(
            segments: const [
              ButtonSegment(value: SnippetResizeMode.clip, label: Text('Clip')),
              ButtonSegment(value: SnippetResizeMode.scale, label: Text('Scale')),
              ButtonSegment(value: SnippetResizeMode.expand, label: Text('Expand')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_mode) {
              SnippetResizeMode.clip =>
                'Stitches outside the new bounds are removed.',
              SnippetResizeMode.scale =>
                'All stitch positions are scaled proportionally.',
              SnippetResizeMode.expand =>
                'Only the declared size changes; no stitches are moved.',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Resize')),
      ],
    );
  }
}

// ─── Palette dots ─────────────────────────────────────────────────────────────

class _SnippetPaletteDots extends StatelessWidget {
  final List<Thread> threads;

  const _SnippetPaletteDots({required this.threads});

  @override
  Widget build(BuildContext context) {
    const maxDots = 12;
    final shown = threads.take(maxDots).toList();
    final overflow = threads.length - shown.length;

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        ...shown.map((t) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12, width: 0.5),
              ),
            )),
        if (overflow > 0)
          Text(
            '+$overflow',
            style: const TextStyle(fontSize: 7, color: Colors.grey),
          ),
      ],
    );
  }
}

// ─── Transform button ──────────────────────────────────────────────────────────

class _TransformButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool iconFlip;
  final VoidCallback onTap;

  const _TransformButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconFlip = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: iconFlip ? 1.5708 : 0, // π/2 = 90° to turn flip icon vertical
                child: Icon(icon, size: 20),
              ),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined,
              size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(
            'No snippets yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('Create one'),
          ),
        ],
      ),
    );
  }
}
