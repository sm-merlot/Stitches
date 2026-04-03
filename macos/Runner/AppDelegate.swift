import Cocoa
import FlutterMacOS

private let kFileOpenChannel = "com.scme0.stitches/file_open"

@main
class AppDelegate: FlutterAppDelegate {
  /// Queued when the app is cold-started with a .stitches file — before
  /// Flutter has registered its getInitialFile handler.
  private var initialFilePath: String?
  private var channel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    _ = ensureChannel() // set up the handler as early as possible
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // ── File open callbacks ────────────────────────────────────────────────────

  // Modern URL-based API (preferred on macOS 12+).
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL && url.path.hasSuffix(".stitches") {
      deliver(url.path)
      break
    }
  }

  // Legacy string-based API — kept for compatibility with older macOS.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard filename.hasSuffix(".stitches") else { return false }
    deliver(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames where filename.hasSuffix(".stitches") {
      deliver(filename)
      break
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns the existing channel or creates it by finding the FlutterViewController
  /// in the window list. MainFlutterWindow extends NSWindow (not FlutterWindow),
  /// so mainFlutterWindow is nil — we scan NSApp.windows instead.
  @discardableResult
  private func ensureChannel() -> FlutterMethodChannel? {
    if let ch = channel { return ch }
    guard let ctrl = NSApp.windows
      .compactMap({ $0.contentViewController as? FlutterViewController })
      .first
    else { return nil }

    let ch = FlutterMethodChannel(name: kFileOpenChannel,
                                  binaryMessenger: ctrl.engine.binaryMessenger)
    ch.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialFile":
        result(self?.initialFilePath)
        self?.initialFilePath = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    return ch
  }

  /// Sends the path to Flutter if the engine is ready, otherwise queues it
  /// for retrieval via getInitialFile.
  private func deliver(_ path: String) {
    if let ch = ensureChannel() {
      ch.invokeMethod("openFile", arguments: path)
    } else {
      initialFilePath = path
    }
  }
}
