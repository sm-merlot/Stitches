import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/snippet.dart';
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
                        childAspectRatio: 0.8,
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

    navigator.pop(); // close the panel

    final result = await navigator.push<Snippet>(
      MaterialPageRoute(
        builder: (_) => SnippetEditorScreen(snippet: snippet),
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
        ],
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
