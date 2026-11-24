import Cocoa
import FlutterMacOS

final class PatchbellStatusMenu: NSObject, NSMenuDelegate {
  private struct AffectedItem {
    let key: String
    let name: String
    let version: String
    let advisories: Int

    init?(_ value: [String: Any]) {
      guard let key = value["key"] as? String,
            let name = value["name"] as? String,
            let version = value["version"] as? String,
            let advisories = value["advisories"] as? Int,
            advisories > 0 else { return nil }
      self.key = key
      self.name = name
      self.version = version
      self.advisories = advisories
    }

    var title: String {
      let headline = "\(name) \(version) · \(advisories)건"
      return headline.count > 85 ? String(headline.prefix(82)) + "…" : headline
    }
  }

  private final class Badge: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  private let window: NSWindow
  private let channel: FlutterMethodChannel
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

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "io.github.h0ng95.patchbell/status_menu",
      binaryMessenger: messenger
    )
    super.init()
    configureStatusItem()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let snapshot = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(snapshot)
      result(nil)
    }
    channel.invokeMethod("requestStatus", arguments: nil)
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
    let label = count == 0 ? "Patchbell" : "Patchbell · 확인할 항목 \(count)개"
    statusItem.button?.toolTip = label
    statusItem.button?.setAccessibilityLabel(label)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    if !affected.isEmpty {
      addLabel("확인할 보안 공지 · \(affected.count)개 항목", to: menu)
      for affectedItem in affected {
        let item = addAction(affectedItem.title, #selector(openItem(_:)), to: menu)
        item.representedObject = affectedItem.key
      }
    } else if loadFailed {
      addLabel("등록 목록을 불러오지 못했어요", to: menu)
    } else if !loaded {
      addLabel("등록 목록 불러오는 중…", to: menu)
    } else if !checking {
      addLabel("표시할 보안 공지가 없어요", to: menu)
    }

    if checking {
      addLabel("보안 공지 확인 중…", to: menu)
    } else if checkFailed {
      addLabel("일부 항목의 조회에 실패했어요", to: menu)
    }

    menu.addItem(.separator())
    addAction("등록하기…", #selector(register), to: menu).isEnabled = loaded
    addAction("내 소프트웨어 열기", #selector(showWindow), to: menu)
    addAction("보안 공지 확인", #selector(check), to: menu).isEnabled = loaded && canCheck && !checking
    let alertSettings = addAction("데스크톱 알림…", #selector(openAlerts), to: menu)
    alertSettings.isEnabled = loaded
    alertSettings.state = notifications ? .on : .off
    menu.addItem(.separator())
    addAction("Patchbell 종료", #selector(quit), to: menu)
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
