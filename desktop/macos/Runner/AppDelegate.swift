import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private(set) var statusMenu: PatchbellStatusMenu?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let window = mainFlutterWindow,
       let controller = window.contentViewController as? FlutterViewController {
      statusMenu = PatchbellStatusMenu(window: window, messenger: controller.engine.binaryMessenger)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    statusMenu?.showWindow()
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
