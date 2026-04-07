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
    // Channel is registered by MainFlutterWindow.awakeFromNib via registerChannel(with:).
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // ── File/folder open callbacks ─────────────────────────────────────────────

  // Modern URL-based API (preferred on macOS 12+).
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL {
      deliver(url.path)
      break
    }
  }

  // Legacy string-based API — kept for compatibility with older macOS.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard isAccepted(filename) else { return false }
    deliver(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames where isAccepted(filename) {
      deliver(filename)
      break
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Called by MainFlutterWindow.awakeFromNib immediately after the
  /// FlutterViewController is created — guaranteed timing, no window scanning.
  func registerChannel(with ctrl: FlutterViewController) {
    guard channel == nil else { return }
    let ch = FlutterMethodChannel(name: kFileOpenChannel,
                                  binaryMessenger: ctrl.engine.binaryMessenger)
    ch.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialFile":
        result(self?.initialFilePath)
        self?.initialFilePath = nil
      case "pickFileOrFolder":
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Open"
        panel.prompt = "Open"
        panel.begin { response in
          if response == .OK, let url = panel.url {
            result(url.path)
          } else {
            result(nil)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  /// Lazy fallback for deliver() when the channel wasn't registered yet
  /// (e.g. cold-start file open before awakeFromNib fires). Scans windows.
  @discardableResult
  private func ensureChannel() -> FlutterMethodChannel? {
    if let ch = channel { return ch }
    guard let ctrl = NSApp.windows
      .compactMap({ $0.contentViewController as? FlutterViewController })
      .first
    else { return nil }
    registerChannel(with: ctrl)
    return channel
  }

  /// Returns true for paths this app handles: .stitches files and directories.
  private func isAccepted(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return isDir.boolValue || path.hasSuffix(".stitches")
  }

  /// Sends the path to Flutter. Directories go as `openFolder`; files as `openFile`.
  /// Queues the path if the engine isn't ready yet.
  private func deliver(_ path: String) {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    let method = isDir.boolValue ? "openFolder" : "openFile"
    if let ch = ensureChannel() {
      ch.invokeMethod(method, arguments: path)
    } else {
      initialFilePath = path // cold-start queue (file or folder)
    }
  }
}
