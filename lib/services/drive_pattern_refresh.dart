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
  // ignore: avoid_print
  print('[DriveRefresh] START fileId=$fileId');
  try {
    final service = await ref.read(googleDriveProvider.notifier).getService();
    if (service == null) {
      // ignore: avoid_print
      print('[DriveRefresh] BAIL: no service');
      return;
    }

    final bytes = await service.downloadFile(fileId);
    // ignore: avoid_print
    print('[DriveRefresh] downloaded ${bytes.length} bytes');

    // Bail out if the user has switched files or started editing.
    final state = ref.read(editorProvider);
    // ignore: avoid_print
    print('[DriveRefresh] state.driveFileId=${state.driveFileId} isDirty=${state.isDirty}');
    if (state.driveFileId != fileId || state.isDirty) {
      // ignore: avoid_print
      print('[DriveRefresh] BAIL: file/dirty check failed');
      return;
    }

    final (pattern, wasCompressed) =
        await FileService.parseBytesToPattern(bytes);

    final stateAfterParse = ref.read(editorProvider);
    if (stateAfterParse.driveFileId != fileId || stateAfterParse.isDirty) {
      // ignore: avoid_print
      print('[DriveRefresh] BAIL: post-parse check failed');
      return;
    }

    await File(tempPath).writeAsBytes(bytes);
    final stat = await File(tempPath).stat();
    PatternCache.put(tempPath, pattern, wasCompressed, stat.modified);

    final current = ref.read(editorProvider);
    if (current.driveFileId != fileId || current.isDirty) {
      // ignore: avoid_print
      print('[DriveRefresh] BAIL: final check failed');
      return;
    }

    // ignore: avoid_print
    print('[DriveRefresh] APPLYING update — viewPan=(${current.viewPanX},${current.viewPanY}) scale=${current.viewScale} mode=${current.mode} filePath=${current.filePath}');

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

    final liveMode = current.mode;

    ref.read(editorProvider.notifier).loadPattern(
          pattern,
          filePath: tempPath,
          driveFileId: fileId,
          driveParentFolderId: parentFolderId,
          compressOnSave: wasCompressed,
          session: liveSession,
        );

    ref.read(editorProvider.notifier).clearPendingFitPage();

    if (liveMode != AppMode.view) {
      ref.read(editorProvider.notifier).setMode(liveMode);
    }
    // ignore: avoid_print
    print('[DriveRefresh] DONE');
  } catch (e, st) {
    // ignore: avoid_print
    print('[DriveRefresh] ERROR: $e\n$st');
  }
}
