import Cocoa
import FlutterMacOS

private let kFileOpenChannel = "com.scme0.stitches/file_open"

@main
class AppDelegate: FlutterAppDelegate {
  /// Stored when the app is cold-started by opening a .stitches file — before
  /// the Flutter engine has set up its method-call handler.
  private var initialFilePath: String?
  private var channel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    guard let ctrl = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    channel = FlutterMethodChannel(
      name: kFileOpenChannel,
      binaryMessenger: ctrl.engine.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialFile":
        result(self?.initialFilePath)
        self?.initialFilePath = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Called when Finder double-clicks a .stitches file (cold or warm start).
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard filename.hasSuffix(".stitches") else { return false }
    deliver(filename)
    return true
  }

  // Called when multiple files are opened at once.
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames where filename.hasSuffix(".stitches") {
      deliver(filename)
      break // open the first; multi-file can be added later
    }
  }

  /// Delivers a file path to Flutter. If the engine isn't ready yet the path
  /// is queued and returned via getInitialFile once Flutter starts up.
  private func deliver(_ path: String) {
    if let ch = channel {
      ch.invokeMethod("openFile", arguments: path)
    } else {
      initialFilePath = path
    }
  }
}
