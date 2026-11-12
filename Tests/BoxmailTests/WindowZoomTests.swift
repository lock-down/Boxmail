import AppKit
import SwiftUI
import Testing

@testable import Boxmail

@Suite(.serialized) @MainActor struct WindowZoomTests {
  @Test func zoomFitsTheDisplayAndRestoresExactPreviousPositionAndSize() {
    let window = makeWindow()
    defer { window.close() }
    let previous = window.frame
    let display = NSRect(x: 0, y: 24, width: 1440, height: 860)
    let controller = WindowZoomController()
    controller.toggle(window, visibleFrame: display)
    #expect(window.frame == display)
    controller.toggle(window, visibleFrame: display)
    #expect(window.frame == previous)
    #expect(Array(window.animationRequests.suffix(2)) == [true, true])
  }

  @Test(arguments: [
    NSRect(x: 0, y: 24, width: 1740, height: 1130),
    NSRect(x: -1024, y: 40, width: 1024, height: 768),
  ])
  func initiallyMaximizedWindowsRestoreToASmallerDefaultAndKeepCycling(display: NSRect) {
    let window = makeWindow()
    defer { window.close() }
    window.setFrame(display, display: true)
    let controller = WindowZoomController()
    controller.toggle(window, visibleFrame: display)
    let restored = window.frame
    #expect(display.contains(restored))
    #expect(restored.width < display.width && restored.height < display.height)
    #expect(abs(restored.midX - display.midX) <= 1 && abs(restored.midY - display.midY) <= 1)
    if display.width >= 1700 {
      #expect(window.contentRect(forFrameRect: restored).size == MainWindowLayout.defaultSize)
    }
    controller.toggle(window, visibleFrame: display)
    #expect(window.frame == display)
    controller.toggle(window, visibleFrame: display)
    #expect(window.frame == restored)
    #expect(Array(window.animationRequests.suffix(3)) == [true, true, true])
  }

  @Test func initialStandardZoomMarginsAlsoRestoreWithoutHistory() {
    let window = makeWindow()
    defer { window.close() }
    let display = NSRect(x: 0, y: 24, width: 1440, height: 860)
    window.setFrame(display.insetBy(dx: 1, dy: 0), display: true)
    WindowZoomController().toggle(window, visibleFrame: display)
    #expect(window.frame.width < display.width && window.frame.height < display.height)
  }

  @Test func manualResizingBecomesTheNextRestoreFrameAndOtherWindowsDoNotShareIt() {
    let window = makeWindow()
    let other = makeWindow()
    defer {
      window.close()
      other.close()
    }
    let display = NSRect(x: 0, y: 24, width: 1440, height: 860)
    let controller = WindowZoomController()
    controller.toggle(window, visibleFrame: display)
    let resized = NSRect(x: 80, y: 90, width: 900, height: 640)
    window.setFrame(resized, display: true)
    controller.toggle(window, visibleFrame: display)
    controller.toggle(window, visibleFrame: display)
    #expect(window.frame == resized)
    let otherFrame = other.frame
    controller.toggle(other, visibleFrame: display)
    controller.toggle(other, visibleFrame: display)
    #expect(other.frame == otherFrame && window.frame == resized)
  }

  @Test func titlebarDoubleClickAndAccessibleActionUseTheSameRestoreState() throws {
    let window = makeWindow()
    defer {
      window.contentView = nil
      window.close()
    }
    let original = window.frame
    let view = WindowTitlebarRegion.DragView(zoom: WindowZoomController())
    defer { view.stopMonitoring() }
    window.contentView = view
    let display = try #require(window.screen?.visibleFrame)
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 2, pressure: 1))
    #expect(view.intercept(event) == nil)
    #expect(window.frame == display)
    #expect(view.accessibilityPerformPress())
    #expect(window.frame == original)
    let outside = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: -10, y: -10),
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 2, clickCount: 2, pressure: 1))
    let ignored = view.intercept(outside) === outside
    #expect(ignored && window.frame == original)
  }

  @Test func mainHeaderRegionsReceiveMouseHitsInsteadOfTheHostingBackground() throws {
    let window = makeWindow()
    defer {
      window.contentView = nil
      window.close()
    }
    window.setContentSize(NSSize(width: 1200, height: 700))
    let host = NSHostingView(rootView: ContentView(store: MailStore()))
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    func regions(_ view: NSView) -> [WindowTitlebarRegion.DragView] {
      (view as? WindowTitlebarRegion.DragView).map { [$0] } ?? view.subviews.flatMap(regions)
    }
    let targets = regions(host).filter { !$0.bounds.isEmpty }
    #expect(targets.count == 2)
    for region in targets {
      let center = region.convert(
        NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: host.superview)
      let receivesMouse = host.hitTest(center) === region
      #expect(receivesMouse)
    }
  }

  private func makeWindow() -> RecordingZoomWindow {
    let window = RecordingZoomWindow(
      contentRect: NSRect(x: 50, y: 70, width: 800, height: 600),
      styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    return window
  }
}

/// Verify native animation requests without running animations in hidden test windows.
@MainActor private final class RecordingZoomWindow: NSWindow {
  var animationRequests: [Bool] = []
  override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
    animationRequests.append(animateFlag)
    super.setFrame(frameRect, display: flag)
  }
}
