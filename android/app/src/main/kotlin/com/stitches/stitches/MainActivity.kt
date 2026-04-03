package com.scme0.stitches

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val channelName = "com.scme0.stitches/file_open"
  private var initialFilePath: String? = null
  private var channel: MethodChannel? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    // Resolve the file path before super.onCreate so it's available when
    // configureFlutterEngine sets up the channel handler.
    initialFilePath = resolveIntent(intent)
    super.onCreate(savedInstanceState)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    val path = resolveIntent(intent) ?: return
    channel?.invokeMethod("openFile", path)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    channel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialFile" -> {
          result.success(initialFilePath)
          initialFilePath = null
        }
        else -> result.notImplemented()
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  private fun resolveIntent(intent: Intent?): String? {
    if (intent?.action != Intent.ACTION_VIEW) return null
    val uri = intent.data ?: return null
    return when (uri.scheme) {
      "file" -> {
        val path = uri.path ?: return null
        if (!path.endsWith(".stitches", ignoreCase = true)) return null
        path
      }
      "content" -> copyContentUri(uri)
      else -> null
    }
  }

  /** Copies a content:// URI to the app cache dir and returns the local path. */
  private fun copyContentUri(uri: Uri): String? {
    return try {
      val displayName = contentResolver
        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        ?: "pattern.stitches"
      // Only handle .stitches files — reject anything else.
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
