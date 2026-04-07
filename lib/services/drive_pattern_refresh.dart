import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor/editor_provider.dart';
import '../providers/google_drive_provider.dart';
import '../services/editor_session_service.dart';
import '../services/file_service.dart';
import '../services/pattern_cache.dart';

/// Downloads the Drive version of the currently-open pattern in the background
/// and silently refreshes the editor — but only if the user has not made any
/// edits since the file was opened.
///
/// Uses the current live editor state (pan/zoom/tool/mode) as the session so
/// that the reload doesn't reset the viewport or kick the user out of stitch
/// mode.
///
/// Parses the downloaded bytes BEFORE writing to disk so the PatternCache is
/// updated atomically with the file write, avoiding a cache-miss window.
Future<void> refreshDrivePatternInBackground(
  WidgetRef ref, {
  required String fileId,
  required String parentFolderId,
  required String tempPath,
}) async {
  try {
    final service = await ref.read(googleDriveProvider.notifier).getService();
    if (service == null) return;

    final bytes = await service.downloadFile(fileId);

    // Bail out if the user has switched files or started editing.
    final state = ref.read(editorProvider);
    if (state.driveFileId != fileId || state.isDirty) return;

    // Parse in background BEFORE touching disk — avoids a window where the
    // file's mtime is newer than the cache entry but the re-parse hasn't
    // completed yet, which would cause a spurious slow cache miss.
    final (pattern, wasCompressed) =
        await FileService.parseBytesToPattern(bytes);

    final stateAfterParse = ref.read(editorProvider);
    if (stateAfterParse.driveFileId != fileId || stateAfterParse.isDirty) {
      return;
    }

    await File(tempPath).writeAsBytes(bytes);
    final stat = await File(tempPath).stat();
    PatternCache.put(tempPath, pattern, wasCompressed, stat.modified);

    // Final check — still the same file and still unedited?
    final current = ref.read(editorProvider);
    if (current.driveFileId != fileId || current.isDirty) return;

    // Build session from the current live state to preserve whatever
    // pan/zoom/tool the user has set since opening — not a stale on-disk
    // snapshot that would reset their viewport.
    final liveSession = EditorSession(
      tool: current.currentTool.name,
      selectedThreadId: current.selectedThreadId,
      blockMode: current.blockMode,
      activeLayerId:
          current.activeLayerId.isEmpty ? null : current.activeLayerId,
      viewPanX: current.viewPanX,
      viewPanY: current.viewPanY,
      viewScale: current.viewScale,
      stitchPage: current.currentPage,
    );

    // Capture mode before loadPattern — it always resets to AppMode.view.
    final liveMode = current.mode;

    ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveFileId: fileId,
          driveParentFolderId: parentFolderId,
          compressOnSave: wasCompressed,
          session: liveSession,
        );

    // loadPattern sets pendingFitPage=0 whenever page mode is enabled, which
    // would snap the canvas to page 0 via the PatternCanvas listener.  We've
    // already captured the correct viewport in liveSession, so suppress the
    // snap by clearing the pending fit immediately.
    ref.read(editorProvider.notifier).clearPendingFitPage();

    // Restore the user's mode if they had already left view mode.
    if (liveMode != AppMode.view) {
      ref.read(editorProvider.notifier).setMode(liveMode);
    }
  } catch (_) {
    // Silently ignore — the user already has a usable cached version.
  }
}
