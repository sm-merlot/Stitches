import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models/storage_location.dart';
import 'providers/editor/editor_provider.dart';
import 'providers/google_drive_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/commands/shortcut_router.dart';

class StitchesApp extends ConsumerStatefulWidget {
  const StitchesApp({super.key});

  @override
  ConsumerState<StitchesApp> createState() => _StitchesAppState();
}

class _StitchesAppState extends ConsumerState<StitchesApp>
    implements ShortcutHandler {
  /// Used by [_openSettings] to push settings onto the navigator from
  /// anywhere — including the macOS menu bar callback.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Register at the bottom of the stack so mode-specific handlers take
    // priority and can consume events before this global handler fires.
    ShortcutRouter.instance.push(this);
  }

  @override
  void dispose() {
    ShortcutRouter.instance.pop(this);
    super.dispose();
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

  void _closeDriveContent() {
    final wsState = ref.read(workspaceProvider);
    if (wsState.workspace is DriveFolder) {
      ref.read(workspaceProvider.notifier).closeWorkspace();
    }
    final editorState = ref.read(editorProvider);
    if (editorState.driveFileId != null) {
      ref.read(editorProvider.notifier).closeFile();
    }
  }

  void _showRevokedDialog() {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Google Drive disconnected'),
        content: const Text(
          'Your session expired or access was revoked — any open Drive files '
          'have been closed. Sign in again from Settings to restore access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.keepScreenOn != next.keepScreenOn) {
        WakelockPlus.toggle(enable: next.keepScreenOn);
      }
    });

    ref.listen<DriveState>(googleDriveProvider, (previous, next) {
      final wasConnected = previous?.status == DriveStatus.connected;
      final nowDisconnected = next.status == DriveStatus.disconnected;
      if (wasConnected && nowDisconnected) {
        _closeDriveContent();
      }
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
