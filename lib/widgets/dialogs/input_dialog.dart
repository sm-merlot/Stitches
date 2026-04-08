import 'package:flutter/material.dart';

/// Shows a single-text-field input AlertDialog. Returns the trimmed string,
/// or null if the user cancelled.
///
/// By default an empty result is treated as cancel and returned as null.
/// Pass [allowEmpty: true] to return the empty string instead — useful when
/// "leave empty for no value" is meaningful (e.g. clearing an optional name).
///
/// Used for rename-* prompts.
Future<String?> inputDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  String confirmLabel = 'Rename',
  String cancelLabel = 'Cancel',
  String? hintText,
  bool allowEmpty = false,
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hintText,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (result == null) return null;
    if (result.isEmpty && !allowEmpty) return null;
    return result;
  } finally {
    controller.dispose();
  }
}
