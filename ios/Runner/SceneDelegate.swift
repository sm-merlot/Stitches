import Flutter
import UIKit

private let kFileOpenChannel = "com.scme0.stitches/file_open"

class SceneDelegate: FlutterSceneDelegate {
  /// Queued path for cold-start file opens (set before Flutter is ready).
  private static var pendingFilePath: String?

  // MARK: - Scene lifecycle

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // After super returns, the FlutterViewController is the root view controller.
    // Register the getInitialFile handler so Flutter can retrieve a cold-start path.
    if let ctrl = flutterViewController {
      let ch = FlutterMethodChannel(name: kFileOpenChannel, binaryMessenger: ctrl.binaryMessenger)
      ch.setMethodCallHandler { call, result in
        switch call.method {
        case "getInitialFile":
          result(SceneDelegate.pendingFilePath)
          SceneDelegate.pendingFilePath = nil
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Check for a file URL delivered at cold-start.
    if let url = connectionOptions.urlContexts.first?.url {
      SceneDelegate.pendingFilePath = copyToTemp(url)
    }
  }

  // Called when a .stitches file is opened into an already-running app.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url,
          let path = copyToTemp(url),
          let ctrl = flutterViewController else { return }
    let ch = FlutterMethodChannel(name: kFileOpenChannel, binaryMessenger: ctrl.binaryMessenger)
    ch.invokeMethod("openFile", arguments: path)
  }

  // MARK: - Helpers

  private var flutterViewController: FlutterViewController? {
    window?.rootViewController as? FlutterViewController
  }

  /// Copies the incoming file URL to the app's temp directory and returns the
  /// new path. Handles security-scoped resources from other app sandboxes.
  private func copyToTemp(_ url: URL) -> String? {
    guard url.isFileURL else { return nil }
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
