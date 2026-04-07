import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-file editor session: the view position, drawing tool, active layer,
/// block mode, etc. that should be restored when the user reopens a file on
/// the same device.
///
/// Stored in SharedPreferences under `editor_session:{fileKey}` where
/// fileKey is `local:{absolutePath}` for local files and `drive:{fileId}`
/// for Google Drive files.
///
/// Note: `stitchMode` is intentionally not persisted — files always open in
/// View mode regardless of the previous session.
class EditorSession {
  /// DrawingTool.name value.
  final String tool;
  final String? selectedThreadId;
  final bool blockMode;
  final String? activeLayerId;
  final double viewPanX;
  final double viewPanY;
  final double viewScale;

  const EditorSession({
    this.tool = 'fullStitch',
    this.selectedThreadId,
    this.blockMode = false,
    this.activeLayerId,
    this.viewPanX = 0,
    this.viewPanY = 0,
    this.viewScale = 0,
  });

  Map<String, dynamic> toJson() => {
        'tool': tool,
        if (selectedThreadId != null) 'selectedThreadId': selectedThreadId,
        'blockMode': blockMode,
        if (activeLayerId != null) 'activeLayerId': activeLayerId,
        'viewPanX': viewPanX,
        'viewPanY': viewPanY,
        'viewScale': viewScale,
      };

  factory EditorSession.fromJson(Map<String, dynamic> json) => EditorSession(
        tool: json['tool'] as String? ?? 'fullStitch',
        selectedThreadId: json['selectedThreadId'] as String?,
        blockMode: json['blockMode'] as bool? ?? false,
        activeLayerId: json['activeLayerId'] as String?,
        viewPanX: (json['viewPanX'] as num?)?.toDouble() ?? 0,
        viewPanY: (json['viewPanY'] as num?)?.toDouble() ?? 0,
        viewScale: (json['viewScale'] as num?)?.toDouble() ?? 0,
      );
}

class EditorSessionService {
  static const String _prefix = 'editor_session:';

  static String _key(String fileKey) => '$_prefix$fileKey';

  static Future<void> save(String fileKey, EditorSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(fileKey), jsonEncode(session.toJson()));
  }

  static Future<EditorSession?> load(String fileKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(fileKey));
    if (raw == null) return null;
    try {
      return EditorSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}
