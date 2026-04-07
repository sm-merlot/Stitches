import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register the file-open method channel here — the FlutterViewController
    // is definitely available at this point in the lifecycle.
    (NSApp.delegate as? AppDelegate)?.registerChannel(with: flutterViewController)

    super.awakeFromNib()
  }
}
