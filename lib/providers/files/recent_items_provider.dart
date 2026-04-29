import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/thumbnail_cache.dart';

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
  /// Cache key for the thumbnail PNG (local → base64 of path; drive file → fileId).
  /// Null for drive folders (no thumbnail).
  final String? thumbnailKey;
  /// If true, this entry exists only to supply thumbnails to a parent folder's
  /// thumbnail strip. It is hidden from the visible recents list.
  final bool thumbnailOnly;
  /// The [id] of the parent folder RecentItem this entry belongs to.
  /// Required for Drive folder strips where path-prefix matching doesn't work.
  final String? parentId;

  const RecentItem({
    required this.id,
    required this.isFolder,
    required this.lastOpened,
    this.isDrive = false,
    this.driveEmail,
    this.driveName,
    this.drivePath,
    this.thumbnailKey,
    this.thumbnailOnly = false,
    this.parentId,
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
        if (thumbnailKey != null) 'thumbnailKey': thumbnailKey,
        if (thumbnailOnly) 'thumbnailOnly': true,
        if (parentId != null) 'parentId': parentId,
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
        thumbnailKey: json['thumbnailKey'] as String?,
        thumbnailOnly: json['thumbnailOnly'] as bool? ?? false,
        parentId: json['parentId'] as String?,
      );
}

/// Returns true on mobile platforms (iOS / Android).
bool get _isMobile =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Returns the home folder path on mobile, or null on desktop/web.
Future<String?> homeFolderPath() async {
  if (!_isMobile) return null;
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
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
    String? thumbnailKey,
    bool thumbnailOnly = false,
    String? parentId,
  }) async {
    // On mobile, suppress the home folder itself from appearing in recents.
    if (_isMobile && !isDrive && isFolder) {
      final home = await homeFolderPath();
      if (home != null && id == home) return;
    }

    final item = RecentItem(
      id: id,
      isFolder: isFolder,
      lastOpened: DateTime.now(),
      isDrive: isDrive,
      driveEmail: driveEmail,
      driveName: driveName,
      drivePath: drivePath,
      thumbnailKey: thumbnailKey,
      thumbnailOnly: thumbnailOnly,
      parentId: parentId,
    );
    var updated = [item, ...state.where((e) => e.id != id)];
    // thumbnailOnly entries are invisible — don't count toward _maxItems.
    final visible = updated.where((e) => !e.thumbnailOnly).toList();
    final thumbOnly = updated.where((e) => e.thumbnailOnly).toList();
    if (visible.length > _maxItems) {
      updated = [...visible.sublist(0, _maxItems), ...thumbOnly];
    }
    state = updated;
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _save();
  }

  /// Remove recents whose local paths no longer exist on disk,
  /// and prune their thumbnail cache entries.
  Future<void> pruneDeletedFiles() async {
    final toRemove = state
        .where((e) => !e.isDrive && !File(e.id).existsSync())
        .toList();
    if (toRemove.isEmpty) return;
    for (final item in toRemove) {
      if (item.thumbnailKey != null) {
        await ThumbnailCache.remove(item.thumbnailKey!);
      }
    }
    state = state.where((e) => e.isDrive || File(e.id).existsSync()).toList();
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
