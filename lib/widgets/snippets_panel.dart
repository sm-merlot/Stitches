import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/snippet.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../screens/snippet_editor_screen.dart';
import 'snippet_thumbnail.dart';

part 'snippets_panel_widgets.dart';

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
                        onSwitchPalette: (idx) => ref
                            .read(editorProvider.notifier)
                            .setSnippetActivePalette(snippets[i].id, idx),
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
    final editorState = ref.read(editorProvider);
    final allSnippets = editorState.pattern.snippets;
    final siblings = allSnippets.where((s) => s.id != snippet?.id).toList();
    final blockMode = editorState.blockMode;

    navigator.pop(); // close the panel

    final result = await navigator.push<Snippet>(
      MaterialPageRoute(
        builder: (_) => SnippetEditorScreen(
          snippet: snippet,
          siblingSnippets: siblings,
          initialBlockMode: blockMode,
        ),
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

