import Flutter
import UIKit

private let kFileOpenChannel = "com.scme0.stitches/file_open"

class SceneDelegate: FlutterSceneDelegate {
  /// Queued path for cold-start opens (file or folder) — set before Flutter is ready.
  private static var pendingPath: String?
  private static var pendingMethod: String?

  // MARK: - Scene lifecycle

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // After super returns the FlutterViewController is the root view controller.
    if let ctrl = flutterViewController {
      let ch = FlutterMethodChannel(name: kFileOpenChannel, binaryMessenger: ctrl.binaryMessenger)
      ch.setMethodCallHandler { _, result in
        result(SceneDelegate.pendingPath)
        SceneDelegate.pendingPath = nil
        SceneDelegate.pendingMethod = nil
      }
    }

    // Check for a URL delivered at cold-start.
    if let url = connectionOptions.urlContexts.first?.url {
      let (method, path) = resolve(url)
      SceneDelegate.pendingPath = path
      SceneDelegate.pendingMethod = method
    }
  }

  // Called when a file or folder is opened into an already-running app.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url,
          let ctrl = flutterViewController else { return }
    let (method, path) = resolve(url)
    guard let path = path else { return }
    let ch = FlutterMethodChannel(name: kFileOpenChannel, binaryMessenger: ctrl.binaryMessenger)
    ch.invokeMethod(method, arguments: path)
  }

  // MARK: - Helpers

  private var flutterViewController: FlutterViewController? {
    window?.rootViewController as? FlutterViewController
  }

  /// Determines the Flutter method name and resolved path for an incoming URL.
  /// Directories are passed through directly; files are copied to the temp dir.
  private func resolve(_ url: URL) -> (method: String, path: String?) {
    guard url.isFileURL else { return ("openFile", nil) }
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    if isDir.boolValue {
      return ("openFolder", url.path)
    } else {
      return ("openFile", copyToTemp(url))
    }
  }

  /// Copies an incoming file URL to the app's temp directory. Handles
  /// security-scoped resources from other app sandboxes.
  private func copyToTemp(_ url: URL) -> String? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent(url.lastPathComponent)
    try? FileManager.default.removeItem(at: dest)
    do {
      try FileManager.default.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      return nil
    }
  }
}
