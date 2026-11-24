import Cocoa
import FlutterMacOS
import XCTest
@testable import Patchbell

class RunnerTests: XCTestCase {
  @MainActor
  func testStatusMenuStartsWithTheAppAndDisplaysAffectedItems() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let status = try XCTUnwrap(delegate.statusMenu)
    let button = try XCTUnwrap(status.statusItem.button)
    let badge = try XCTUnwrap(button.subviews.compactMap { $0 as? NSTextField }.first)
    let menu = try XCTUnwrap(status.statusItem.menu)
    XCTAssertTrue(status.statusItem.isVisible)
    XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))

    status.update([
      "loaded": true,
      "affected": [
        ["key": "flutter:flutter:3.27.4", "name": "Flutter SDK", "version": "3.27.4", "advisories": 2]
      ],
    ])
    status.menuNeedsUpdate(menu)

    XCTAssertFalse(badge.isHidden)
    XCTAssertEqual(badge.stringValue, "1")
    XCTAssertTrue(menu.items.contains { $0.title == "Flutter SDK 3.27.4 · 2건" })
    XCTAssertTrue(menu.items.contains { $0.title == "등록하기…" && $0.isEnabled })
    XCTAssertTrue(menu.items.contains { $0.title == "설치 버전 찾기…" && $0.isEnabled })

    status.update(["loaded": true, "affected": []])
    XCTAssertTrue(badge.isHidden)
  }
}
