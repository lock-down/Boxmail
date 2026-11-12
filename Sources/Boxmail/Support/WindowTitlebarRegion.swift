import AppKit
import OSLog
import SwiftUI

/// State belongs to the main content view, so either empty titlebar region can restore it.
@MainActor final class WindowZoomController {
  private static let logger = Logger(subsystem: "com.boxmail.desktop", category: "Window")
  private weak var owner: NSWindow?
  private var previousFrame: NSRect?
  private var maximizedFrame: NSRect?

  func toggle(_ window: NSWindow, visibleFrame: NSRect) {
    guard window.styleMask.contains(.resizable), !window.styleMask.contains(.fullScreen),
      window.attachedSheet == nil, !visibleFrame.isEmpty
    else { return }
    if owner !== window {
      previousFrame = nil
      maximizedFrame = nil
      owner = window
    }
    if matches(window.frame, visibleFrame)
      || maximizedFrame.map({ matches(window.frame, $0) }) == true
    {
      let restoredFrame =
        previousFrame ?? MainWindowLayout.defaultRestoreFrame(for: window, within: visibleFrame)
      self.previousFrame = nil
      self.maximizedFrame = nil
      window.setFrame(restoredFrame, display: true, animate: true)
      Self.logger.info(
        "window.zoom.restore width=\(Int(window.frame.width)) height=\(Int(window.frame.height))")
    } else {
      previousFrame = window.frame
      maximizedFrame = visibleFrame
      window.setFrame(visibleFrame, display: true, animate: true)
      Self.logger.info(
        "window.zoom.maximize width=\(Int(window.frame.width)) height=\(Int(window.frame.height))")
    }
  }
  private func matches(_ a: NSRect, _ b: NSRect) -> Bool {
    // AppKit's standard zoom frame can differ by a couple of points at the edges.
    abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
      && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
  }
}

/// Used only in empty header space; search fields and toolbar buttons keep their native clicks.
struct WindowTitlebarRegion: NSViewRepresentable {
  let zoom: WindowZoomController
  func makeNSView(context: Context) -> DragView { DragView(zoom: zoom) }
  func updateNSView(_ view: DragView, context: Context) { view.zoom = zoom }
  static func dismantleNSView(_ view: DragView, coordinator: ()) { view.stopMonitoring() }

  final class DragView: NSView {
    private static let logger = Logger(subsystem: "com.boxmail.desktop", category: "Window")
    var zoom: WindowZoomController
    private var monitor: Any?
    init(zoom: WindowZoomController) {
      self.zoom = zoom
      super.init(frame: .zero)
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel("最大化或恢复窗口")
      toolTip = "双击最大化或恢复窗口，拖动移动窗口"
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      // Hidden titlebars can consume double clicks before NSView.mouseDown.
      // Intercept only this window's empty header bounds, before AppKit's policy.
      monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        MainActor.assumeIsolated {
          guard let self else { return event }
          return self.intercept(event)
        }
      }
    }
    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
    func intercept(_ event: NSEvent) -> NSEvent? {
      guard event.clickCount == 2, let window, event.window === window,
        bounds.contains(convert(event.locationInWindow, from: nil)), let screen = window.screen
      else { return event }
      Self.logger.info("window.titlebar.double-click")
      zoom.toggle(window, visibleFrame: screen.visibleFrame)
      return nil
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
      guard let window, let screen = window.screen else { return false }
      zoom.toggle(window, visibleFrame: screen.visibleFrame)
      return true
    }
    override func mouseDown(with event: NSEvent) {
      guard let window else { return }
      if event.clickCount == 2, let screen = window.screen {
        Self.logger.info("window.titlebar.double-click")
        zoom.toggle(window, visibleFrame: screen.visibleFrame)
      } else if event.clickCount == 1 {
        window.performDrag(with: event)
      }
    }
  }
}
