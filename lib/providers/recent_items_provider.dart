import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentItem {
  /// For local items: the file/folder path.
  /// For Drive items: the folderId.
  final String id;
  final bool isFolder;
  final bool isDrive;
  /// Email of the Google account (Drive items only).
  final String? driveEmail;
  /// Display name of the Drive file/folder.
  final String? driveName;
  /// Breadcrumb path within Drive, e.g. "My Drive › Projects › Patterns".
  final String? drivePath;
  final DateTime lastOpened;

  const RecentItem({
    required this.id,
    required this.isFolder,
    required this.lastOpened,
    this.isDrive = false,
    this.driveEmail,
    this.driveName,
    this.drivePath,
  });

  List<String> get _localPathParts => id.split(RegExp(r'[/\\]'));

  String get displayName {
    if (isDrive) return driveName ?? 'Drive Folder';
    final seg = _localPathParts.last;
    if (isFolder) return seg;
    return seg.endsWith('.stitches') ? seg.substring(0, seg.length - 8) : seg;
  }

  String get displayPath {
    if (isDrive) {
      final account = driveEmail ?? 'Google Drive';
      if (drivePath != null) return '$drivePath  ·  $account';
      return 'Google Drive · $account';
    }
    final parts = _localPathParts;
    if (parts.length >= 2) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
    return id;
  }

  String get relativeTime {
    final diff = DateTime.now().difference(lastOpened);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).round()}w ago';
    return '${(diff.inDays / 30).round()}mo ago';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'isFolder': isFolder,
        'isDrive': isDrive,
        if (driveEmail != null) 'driveEmail': driveEmail,
        if (driveName != null) 'driveName': driveName,
        if (drivePath != null) 'drivePath': drivePath,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
      };

  factory RecentItem.fromJson(Map<String, dynamic> json) => RecentItem(
        // 'path' key is the old format — fall back for backward compatibility
        id: (json['id'] ?? json['path']) as String,
        isFolder: json['isFolder'] as bool,
        lastOpened:
            DateTime.fromMillisecondsSinceEpoch(json['lastOpened'] as int),
        isDrive: json['isDrive'] as bool? ?? false,
        driveEmail: json['driveEmail'] as String?,
        driveName: json['driveName'] as String?,
        drivePath: json['drivePath'] as String?,
      );
}

class RecentItemsNotifier extends Notifier<List<RecentItem>> {
  static const _key = 'recent_items';
  static const _maxItems = 20;

  @override
  List<RecentItem> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => RecentItem.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      // Corrupt or unreadable prefs data — silently reset to empty list.
    }
  }

  Future<void> add(
    String id, {
    required bool isFolder,
    bool isDrive = false,
    String? driveEmail,
    String? driveName,
    String? drivePath,
  }) async {
    final item = RecentItem(
      id: id,
      isFolder: isFolder,
      lastOpened: DateTime.now(),
      isDrive: isDrive,
      driveEmail: driveEmail,
      driveName: driveName,
      drivePath: drivePath,
    );
    var updated = [item, ...state.where((e) => e.id != id)];
    if (updated.length > _maxItems) updated = updated.sublist(0, _maxItems);
    state = updated;
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }
}

final recentItemsProvider =
    NotifierProvider<RecentItemsNotifier, List<RecentItem>>(
        RecentItemsNotifier.new);
