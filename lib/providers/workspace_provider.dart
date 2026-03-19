import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/storage_location.dart';

// ---------------------------------------------------------------------------
// Clipboard
// ---------------------------------------------------------------------------

enum ClipboardOp { copy, cut }

class ClipboardEntry {
  final PatternFile file;
  final ClipboardOp op;

  const ClipboardEntry({required this.file, required this.op});
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class WorkspaceState {
  /// The currently open workspace folder (null = no folder open).
  final StorageLocation? workspace;

  /// Whether the file sidebar is visible.
  final bool sidebarVisible;

  /// IDs of folders whose tree nodes are expanded in the sidebar.
  final Set<String> expandedFolderIds;

  /// File pending copy or cut.
  final ClipboardEntry? clipboard;

  const WorkspaceState({
    this.workspace,
    this.sidebarVisible = true,
    this.expandedFolderIds = const {},
    this.clipboard,
  });

  WorkspaceState copyWith({
    StorageLocation? workspace,
    bool clearWorkspace = false,
    bool? sidebarVisible,
    Set<String>? expandedFolderIds,
    ClipboardEntry? clipboard,
    bool clearClipboard = false,
  }) {
    return WorkspaceState(
      workspace: clearWorkspace ? null : workspace ?? this.workspace,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      expandedFolderIds: expandedFolderIds ?? this.expandedFolderIds,
      clipboard: clearClipboard ? null : clipboard ?? this.clipboard,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  static const _keyPinnedLocations = 'pinned_locations';
  static const _keyLastWorkspace = 'last_workspace';

  @override
  WorkspaceState build() => const WorkspaceState();

  // -------------------------------------------------------------------------
  // Workspace
  // -------------------------------------------------------------------------

  Future<void> openWorkspace(StorageLocation location) async {
    state = state.copyWith(
      workspace: location,
      expandedFolderIds: {location.id},
    );
    await _persistLastWorkspace(location);
  }

  void closeWorkspace() {
    state = state.copyWith(clearWorkspace: true, expandedFolderIds: {});
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  void toggleSidebar() {
    state = state.copyWith(sidebarVisible: !state.sidebarVisible);
  }

  void setSidebarVisible(bool visible) {
    state = state.copyWith(sidebarVisible: visible);
  }

  // -------------------------------------------------------------------------
  // Tree expand / collapse
  // -------------------------------------------------------------------------

  void toggleFolder(String folderId) {
    final ids = state.expandedFolderIds;
    state = state.copyWith(
      expandedFolderIds: ids.contains(folderId)
          ? ids.difference({folderId})
          : {...ids, folderId},
    );
  }

  void expandFolder(String folderId) {
    state = state.copyWith(
      expandedFolderIds: {...state.expandedFolderIds, folderId},
    );
  }

  // -------------------------------------------------------------------------
  // Clipboard
  // -------------------------------------------------------------------------

  void copyFile(PatternFile file) {
    state = state.copyWith(
      clipboard: ClipboardEntry(file: file, op: ClipboardOp.copy),
    );
  }

  void cutFile(PatternFile file) {
    state = state.copyWith(
      clipboard: ClipboardEntry(file: file, op: ClipboardOp.cut),
    );
  }

  void clearClipboard() {
    state = state.copyWith(clearClipboard: true);
  }

  // -------------------------------------------------------------------------
  // Pinned locations (persisted list shown on home screen)
  // -------------------------------------------------------------------------

  Future<List<StorageLocation>> loadPinnedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyPinnedLocations) ?? [];
    return raw.map(_deserializeLocation).whereType<StorageLocation>().toList();
  }

  Future<void> pinLocation(StorageLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyPinnedLocations) ?? [];
    final serialized = _serializeLocation(location);
    if (!raw.contains(serialized)) {
      await prefs.setStringList(_keyPinnedLocations, [...raw, serialized]);
    }
  }

  Future<void> unpinLocation(StorageLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyPinnedLocations) ?? [];
    final serialized = _serializeLocation(location);
    await prefs.setStringList(
      _keyPinnedLocations,
      raw.where((s) => s != serialized).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Persistence helpers
  // -------------------------------------------------------------------------

  /// Returns the last-used workspace path (if any) without activating it.
  /// Used by the home screen to show the last workspace in the recent list
  /// without triggering a directory listing (which needs a fresh picker grant).
  Future<StorageLocation?> readLastWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLastWorkspace);
    if (raw == null) return null;
    return _deserializeLocation(raw);
  }

  Future<void> _persistLastWorkspace(StorageLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastWorkspace, _serializeLocation(location));
  }

  String _serializeLocation(StorageLocation location) {
    return switch (location) {
      LocalFolder f => jsonEncode({'type': 'local', 'path': f.path}),
      DriveFolder f => jsonEncode({
          'type': 'drive',
          'folderId': f.folderId,
          'name': f.name,
          'parentId': f.parentId,
        }),
    };
  }

  StorageLocation? _deserializeLocation(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return switch (map['type'] as String) {
        'local' => LocalFolder(map['path'] as String),
        'drive' => DriveFolder(
            folderId: map['folderId'] as String,
            name: map['name'] as String,
            parentId: map['parentId'] as String?,
          ),
        _ => null,
      };
    } catch (_) {
      // Corrupt or unrecognised prefs data — treat as no saved workspace.
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final workspaceProvider =
    NotifierProvider<WorkspaceNotifier, WorkspaceState>(WorkspaceNotifier.new);
