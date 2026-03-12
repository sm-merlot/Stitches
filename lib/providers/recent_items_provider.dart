import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentItem {
  final String path;
  final bool isFolder;
  final DateTime lastOpened;

  const RecentItem({
    required this.path,
    required this.isFolder,
    required this.lastOpened,
  });

  /// Filename without extension (for files), or folder name (for folders).
  String get displayName {
    final seg = path.split('/').last.split('\\').last;
    if (isFolder) return seg;
    return seg.endsWith('.stitchx') ? seg.substring(0, seg.length - 8) : seg;
  }

  /// Parent directory path shown as subtitle.
  String get displayPath {
    final parts = path.split('/');
    if (parts.length >= 2) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
    return path;
  }

  /// Human-readable relative time string.
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
        'path': path,
        'isFolder': isFolder,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
      };

  factory RecentItem.fromJson(Map<String, dynamic> json) => RecentItem(
        path: json['path'] as String,
        isFolder: json['isFolder'] as bool,
        lastOpened:
            DateTime.fromMillisecondsSinceEpoch(json['lastOpened'] as int),
      );
}

class RecentItemsNotifier extends StateNotifier<List<RecentItem>> {
  static const _key = 'recent_items';
  static const _maxItems = 20;

  RecentItemsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => RecentItem.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {}
  }

  Future<void> add(String path, {required bool isFolder}) async {
    final item = RecentItem(
        path: path, isFolder: isFolder, lastOpened: DateTime.now());
    var updated = [item, ...state.where((e) => e.path != path)];
    if (updated.length > _maxItems) updated = updated.sublist(0, _maxItems);
    state = updated;
    await _save();
  }

  Future<void> remove(String path) async {
    state = state.where((e) => e.path != path).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }
}

final recentItemsProvider =
    StateNotifierProvider<RecentItemsNotifier, List<RecentItem>>(
        (_) => RecentItemsNotifier());
