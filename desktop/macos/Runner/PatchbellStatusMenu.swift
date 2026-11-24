import Cocoa
import FlutterMacOS
import UserNotifications

final class PatchbellStatusMenu: NSObject, NSMenuDelegate, UNUserNotificationCenterDelegate {
  private struct AffectedItem {
    let key: String
    let title: String

    init?(_ value: [String: Any]) {
      guard let key = value["key"] as? String,
            let headline = value["title"] as? String else { return nil }
      self.key = key
      title = headline.count > 85 ? String(headline.prefix(82)) + "…" : headline
    }
  }

  private final class Badge: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  private let window: NSWindow
  private let channel: FlutterMethodChannel
  private let notificationCenter = UNUserNotificationCenter.current()
  let statusItem = NSStatusBar.system.statusItem(withLength: 28)
  private let badge = Badge(labelWithString: "")
  private var badgeWidth: NSLayoutConstraint?
  private var affected: [AffectedItem] = []
  private var loaded = false
  private var loadFailed = false
  private var checking = false
  private var canCheck = false
  private var checkFailed = false
  private var notifications = false
  private var labels: [String: String] = [:]

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "io.github.h0ng95.patchbell/status_menu",
      binaryMessenger: messenger
    )
    super.init()
    configureStatusItem()
    notificationCenter.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "update":
        guard let snapshot = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_status", message: "Expected menu status", details: nil))
          return
        }
        self?.update(snapshot)
        result(nil)
      case "discoveryLocations":
        result(self?.discoveryLocations())
      case "requestNotifications":
        self?.requestNotifications(result)
      case "showNotification":
        self?.showNotification(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel.invokeMethod("requestStatus", arguments: nil)
  }

  private func discoveryLocations() -> [String: String] {
    var locations = ["home": NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()]
    if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
      locations["codePath"] = editor.path
      locations["codeVersion"] = Bundle(url: editor)?
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
    return locations
  }

  private func requestNotifications(_ result: @escaping FlutterResult) {
    notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "notification_permission", message: error.localizedDescription, details: nil))
        } else {
          result(granted)
        }
      }
    }
  }

  private func showNotification(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let data = arguments as? [String: Any],
          let id = data["id"] as? Int,
          let title = data["title"] as? String,
          let body = data["body"] as? String else {
      result(FlutterError(code: "invalid_notification", message: nil, details: nil))
      return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let itemKey = data["itemKey"] as? String {
      content.userInfo = ["itemKey": itemKey]
    }
    let request = UNNotificationRequest(identifier: String(id), content: content, trigger: nil)
    notificationCenter.add(request) { [weak self] error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "notification_delivery", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
          #if DEBUG
          self?.checkDeliveredNotification(request.identifier)
          #endif
        }
      }
    }
  }

  #if DEBUG
  private func checkDeliveredNotification(_ identifier: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.notificationCenter.getDeliveredNotifications { delivered in
        NSLog("Patchbell notification in macOS Notification Center: %@",
              String(delivered.contains { $0.request.identifier == identifier }))
      }
    }
  }
  #endif

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completion([.banner, .list, .sound])
    } else {
      completion([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completion: @escaping () -> Void
  ) {
    DispatchQueue.main.async {
      if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
        if let key = response.notification.request.content.userInfo["itemKey"] as? String {
          self.sendWindowAction("openItem", arguments: key)
        } else {
          self.showWindow()
        }
      }
      completion()
    }
  }

  private func configureStatusItem() {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    menuNeedsUpdate(menu)
    statusItem.menu = menu

    guard let button = statusItem.button else { return }
    button.imagePosition = .imageLeft
    if #available(macOS 11.0, *),
       let image = NSImage(systemSymbolName: "bell", accessibilityDescription: nil) {
      image.isTemplate = true
      button.image = image
    } else {
      button.title = "♢"
    }

    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.wantsLayer = true
    badge.layer?.backgroundColor = NSColor.systemRed.cgColor
    badge.layer?.cornerRadius = 6
    badge.alignment = .center
    badge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    badge.textColor = .white
    badge.isHidden = true
    badge.setAccessibilityElement(false)
    button.addSubview(badge)
    let width = badge.widthAnchor.constraint(equalToConstant: 12)
    badgeWidth = width
    NSLayoutConstraint.activate([
      badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
      badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 4),
      badge.heightAnchor.constraint(equalToConstant: 12),
      width,
    ])
    updateBadge()
  }

  func update(_ snapshot: [String: Any]) {
    loaded = snapshot["loaded"] as? Bool ?? false
    loadFailed = snapshot["loadFailed"] as? Bool ?? false
    checking = snapshot["checking"] as? Bool ?? false
    canCheck = snapshot["canCheck"] as? Bool ?? false
    checkFailed = snapshot["checkFailed"] as? Bool ?? false
    notifications = snapshot["notifications"] as? Bool ?? false
    labels = snapshot["labels"] as? [String: String] ?? [:]
    affected = (snapshot["affected"] as? [[String: Any]] ?? []).compactMap(AffectedItem.init)
    updateBadge()
  }

  private func updateBadge() {
    let count = affected.count
    let displayedCount = count > 99 ? "99+" : String(count)
    let width: CGFloat = count > 99 ? 22 : (count > 9 ? 17 : 12)
    badge.stringValue = displayedCount
    badge.isHidden = count == 0
    badgeWidth?.constant = width
    statusItem.length = count == 0 ? 28 : 22 + width
    let label = count == 0 ? "Patchbell" : (labels["badge"] ?? "Patchbell")
    statusItem.button?.toolTip = label
    statusItem.button?.setAccessibilityLabel(label)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    if !affected.isEmpty {
      addLabel(labels["affected"] ?? "Security advisories", to: menu)
      for affectedItem in affected {
        let item = addAction(affectedItem.title, #selector(openItem(_:)), to: menu)
        item.representedObject = affectedItem.key
      }
    } else if loadFailed {
      addLabel(labels["loadFailed"] ?? "Could not load tracked items", to: menu)
    } else if !loaded {
      addLabel(labels["loading"] ?? "Loading tracked items…", to: menu)
    } else if !checking {
      addLabel(labels["noAdvisories"] ?? "No advisories to show", to: menu)
    }

    if checking {
      addLabel(labels["checking"] ?? "Checking advisories…", to: menu)
    } else if checkFailed {
      addLabel(labels["checkFailed"] ?? "Some items could not be checked", to: menu)
    }

    menu.addItem(.separator())
    addAction(labels["register"] ?? "Add software…", #selector(register), to: menu).isEnabled = loaded
    addAction(labels["scan"] ?? "Find installed versions…", #selector(scanInstalled), to: menu).isEnabled = loaded
    addAction(labels["open"] ?? "Open My Software", #selector(showWindow), to: menu)
    addAction(labels["check"] ?? "Check advisories", #selector(check), to: menu).isEnabled = loaded && canCheck && !checking
    let alertSettings = addAction(labels["alerts"] ?? "Desktop alerts…", #selector(openAlerts), to: menu)
    alertSettings.isEnabled = loaded
    alertSettings.state = notifications ? .on : .off
    menu.addItem(.separator())
    addAction(labels["quit"] ?? "Quit Patchbell", #selector(quit), to: menu)
  }

  private func addLabel(_ title: String, to menu: NSMenu) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    menu.addItem(item)
  }

  @discardableResult
  private func addAction(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return item
  }

  @objc func showWindow() {
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
  }

  private func sendWindowAction(_ method: String, arguments: Any? = nil) {
    showWindow()
    channel.invokeMethod(method, arguments: arguments)
  }

  @objc private func openItem(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    sendWindowAction("openItem", arguments: key)
  }

  @objc private func register() {
    sendWindowAction("register")
  }

  @objc private func scanInstalled() {
    sendWindowAction("scanInstalled")
  }

  @objc private func openAlerts() {
    sendWindowAction("openAlerts")
  }

  @objc private func check() {
    channel.invokeMethod("check", arguments: nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
