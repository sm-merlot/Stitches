package com.scme0.stitches

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val channelName = "com.scme0.stitches/file_open"

  // Stores both the resolved path and whether it's a folder so the correct
  // Flutter method can be called once the channel is ready.
  private var initialPath: String? = null
  private var initialIsFolder: Boolean = false
  private var channel: MethodChannel? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    val (path, isFolder) = resolveIntent(intent)
    initialPath = path
    initialIsFolder = isFolder
    super.onCreate(savedInstanceState)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    val (path, isFolder) = resolveIntent(intent)
    if (path != null) {
      channel?.invokeMethod(if (isFolder) "openFolder" else "openFile", path)
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    channel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialFile" -> {
          result.success(initialPath)
          initialPath = null
        }
        else -> result.notImplemented()
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /** Returns (resolvedPath, isFolder). Path is null if the intent isn't handled. */
  private fun resolveIntent(intent: Intent?): Pair<String?, Boolean> {
    if (intent?.action != Intent.ACTION_VIEW) return Pair(null, false)
    val uri = intent.data ?: return Pair(null, false)
    val mimeType = intent.type ?: ""

    // Directory MIME types sent by file managers
    if (mimeType == "inode/directory" || mimeType == "resource/folder" ||
        mimeType == "vnd.android.document/directory") {
      val path = resolveDirectoryUri(uri)
      return Pair(path, path != null)
    }

    return when (uri.scheme) {
      "file" -> {
        val path = uri.path ?: return Pair(null, false)
        val dir = File(path).isDirectory
        if (dir) return Pair(path, true)
        if (!path.endsWith(".stitches", ignoreCase = true)) return Pair(null, false)
        Pair(path, false)
      }
      "content" -> {
        // Check for a document tree (folder) URI first
        if (DocumentsContract.isTreeUri(uri)) {
          val path = resolveDirectoryUri(uri)
          return Pair(path, path != null)
        }
        Pair(copyContentUri(uri), false)
      }
      else -> Pair(null, false)
    }
  }

  /**
   * Attempts to resolve a directory URI to a local file system path.
   * Works reliably for file:// URIs and content:// URIs on primary storage.
   * Returns null if the path cannot be determined (e.g. secondary storage,
   * cloud providers) — the caller should handle this gracefully.
   */
  private fun resolveDirectoryUri(uri: Uri): String? {
    return try {
      when (uri.scheme) {
        "file" -> uri.path
        "content" -> {
          val docId = if (DocumentsContract.isTreeUri(uri))
            DocumentsContract.getTreeDocumentId(uri)
          else
            DocumentsContract.getDocumentId(uri)
          // Primary external storage: "primary:path/to/dir"
          if (docId.startsWith("primary:")) {
            Environment.getExternalStorageDirectory().absolutePath +
                "/" + docId.removePrefix("primary:")
          } else {
            null
          }
        }
        else -> null
      }
    } catch (_: Exception) {
      null
    }
  }

  /** Copies a content:// file URI to the app cache dir and returns the local path. */
  private fun copyContentUri(uri: Uri): String? {
    return try {
      val displayName = contentResolver
        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        ?: "pattern.stitches"
      if (!displayName.endsWith(".stitches", ignoreCase = true)) return null
      val dest = File(cacheDir, displayName)
      contentResolver.openInputStream(uri)?.use { input ->
        FileOutputStream(dest).use { output -> input.copyTo(output) }
      }
      dest.absolutePath
    } catch (_: Exception) {
      null
    }
  }
}
