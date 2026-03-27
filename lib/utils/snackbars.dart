import 'package:flutter/material.dart';

/// Shows a red error snackbar.
void showError(BuildContext context, String message,
    {Duration duration = const Duration(seconds: 4)}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red.shade700,
      duration: duration,
    ),
  );
}

/// Shows a default (neutral) success snackbar.
void showSuccess(BuildContext context, String message,
    {Duration duration = const Duration(seconds: 4)}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: duration),
  );
}

/// Shows an orange warning snackbar.
void showWarning(BuildContext context, String message,
    {Duration duration = const Duration(seconds: 4)}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.orange.shade700,
      duration: duration,
    ),
  );
}
