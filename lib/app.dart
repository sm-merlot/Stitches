import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models/storage_location.dart';
import 'providers/editor/editor_provider.dart';
import 'providers/files/folder_contents_provider.dart';
import 'providers/google_drive_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/drive/drive_pattern_refresh.dart';
import 'utils/commands/shortcut_router.dart';

class StitchesApp extends ConsumerStatefulWidget {
  const StitchesApp({super.key});

  @override
  ConsumerState<StitchesApp> createState() => _StitchesAppState();
}

class _StitchesAppState extends ConsumerState<StitchesApp>
    implements ShortcutHandler, WidgetsBindingObserver {
  /// Used by [_openSettings] to push settings onto the navigator from
  /// anywhere — including the macOS menu bar callback.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register at the bottom of the stack so mode-specific handlers take
    // priority and can consume events before this global handler fires.
    ShortcutRouter.instance.push(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShortcutRouter.instance.pop(this);
    super.dispose();
  }

  /// Triggered when the app returns to the foreground (including device unlock).
  /// Re-downloads the open Drive file if it hasn't been locally edited so that
  /// progress marked on another device is reflected without a manual refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final editor = ref.read(editorProvider);
    final fileId = editor.driveFileId;
    final parentFolderId = editor.driveParentFolderId;
    final tempPath = editor.filePath;
    if (fileId != null && parentFolderId != null && tempPath != null &&
        !editor.isDirty) {
      refreshDrivePatternInBackground(
        ref,
        fileId: fileId,
        parentFolderId: parentFolderId,
        tempPath: tempPath,
      );
    }
  }

  @override
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.comma) return false;
    // macOS: Cmd+, is handled by PlatformMenuBar at the system level.
    // Windows / Linux: Ctrl+, opens settings.
    if (defaultTargetPlatform == TargetPlatform.macOS) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    _openSettings();
    return true;
  }

  void _openSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  /// Closes any open Drive workspace/file and pops to home with a snackbar.
  /// Does nothing if no Drive content is currently open.
  void _closeDriveContent() {
    final wsState = ref.read(workspaceProvider);
    final editorState = ref.read(editorProvider);
    final hadDriveWorkspace = wsState.workspace is DriveFolder;
    final hadDriveFile = editorState.driveFileId != null;

    if (!hadDriveWorkspace && !hadDriveFile) return;

    if (hadDriveWorkspace) ref.read(workspaceProvider.notifier).closeWorkspace();
    if (hadDriveFile) ref.read(editorProvider.notifier).closeFile();

    // Defer navigation — calling popUntil during a Riverpod listener (which
    // fires in the build phase) causes a navigator assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null) {
          final what = hadDriveWorkspace ? 'workspace' : 'file';
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Signed out of Google Drive — $what closed')),
          );
        }
      });
    });
  }

  Future<void> _showRevokedDialog() async {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    final result = await showDialog<_RevokedResult>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const _RevokedDialog(),
    );
    // Dismiss (or cancel during sign-in): close workspace and go home.
    // signedIn: dialog auto-closed after OAuth; workspace is still open, done.
    if (result != _RevokedResult.signedIn) {
      _closeDriveContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.keepScreenOn != next.keepScreenOn) {
        WakelockPlus.toggle(enable: next.keepScreenOn);
      }
    });

    ref.listen<DriveState>(googleDriveProvider, (previous, next) {
      // Regular sign-out — close Drive content and return to home.
      if (previous?.status == DriveStatus.connected &&
          next.status == DriveStatus.disconnected &&
          !next.wasRevoked) {
        _closeDriveContent();
      }
      // Revocation — show blocking dialog while workspace stays open behind it.
      if (next.wasRevoked && !(previous?.wasRevoked ?? false)) {
        ref.read(googleDriveProvider.notifier).clearRevokedFlag();
        _showRevokedDialog();
      }
    });

    final keepScreenOn = ref.read(settingsProvider).keepScreenOn;
    if (keepScreenOn) WakelockPlus.enable();

    final app = MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Stitches',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
      ),
      home: const HomeScreen(),
    );

    // PlatformMenuBar is macOS-only — adds Preferences… to the app menu.
    // On other platforms it is a no-op, but guard explicitly so the
    // PlatformProvidedMenuItem types don't cause issues on non-macOS.
    if (defaultTargetPlatform != TargetPlatform.macOS) return app;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Stitches',
          menus: [
            const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.about),
            PlatformMenuItem(
              label: 'Preferences…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.comma, meta: true),
              onSelected: _openSettings,
            ),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide),
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications),
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit),
            ]),
          ],
        ),
      ],
      child: app,
    );
  }
}

// ---------------------------------------------------------------------------
// Revocation dialog
// ---------------------------------------------------------------------------

enum _RevokedResult { dismiss, signedIn }

class _RevokedDialog extends ConsumerStatefulWidget {
  const _RevokedDialog();

  @override
  ConsumerState<_RevokedDialog> createState() => _RevokedDialogState();
}

class _RevokedDialogState extends ConsumerState<_RevokedDialog> {
  bool _signingIn = false;
  String? _error;

  void _onReconnected() {
    // Refresh the workspace folder listing so the sidebar is up to date.
    final workspace = ref.read(workspaceProvider).workspace;
    if (workspace != null) {
      refreshFolder(ref, workspace);
    }

    // Re-download the open Drive file if it hasn't been edited.
    final editor = ref.read(editorProvider);
    final fileId = editor.driveFileId;
    final parentFolderId = editor.driveParentFolderId;
    final tempPath = editor.filePath;
    if (fileId != null && parentFolderId != null && tempPath != null) {
      refreshDrivePatternInBackground(
        ref,
        fileId: fileId,
        parentFolderId: parentFolderId,
        tempPath: tempPath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DriveState>(googleDriveProvider, (previous, next) {
      if (!mounted) return;
      if (next.status == DriveStatus.connected) {
        _onReconnected();
        Navigator.of(context).pop(_RevokedResult.signedIn);
      } else if (_signingIn && next.status == DriveStatus.error) {
        setState(() {
          _signingIn = false;
          _error = next.error ?? 'Sign-in failed. Try again.';
        });
      }
    });

    return AlertDialog(
      title: const Text('Google Drive disconnected'),
      content: _signingIn
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('Waiting for sign-in…'),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your session expired or access was revoked.'),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
      actions: _signingIn
          ? [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_RevokedResult.dismiss),
                child: const Text('Cancel'),
              ),
            ]
          : [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_RevokedResult.dismiss),
                child: const Text('Dismiss'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _signingIn = true;
                    _error = null;
                  });
                  ref.read(googleDriveProvider.notifier).connect();
                },
                child: const Text('Sign in again'),
              ),
            ],
    );
  }
}
