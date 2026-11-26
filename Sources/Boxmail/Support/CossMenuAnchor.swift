import AppKit
import SwiftUI

struct CossMenuAnchor: NSViewRepresentable {
  @Binding var isOpen: Bool
  let items: () -> [CossMenuItem]
  let width: CGFloat
  var prefersSelection = false
  var trailing = false
  var dismissTree: (() -> Void)? = nil

  func makeNSView(context: Context) -> CossMenuAnchorView { CossMenuAnchorView() }

  func updateNSView(_ view: CossMenuAnchorView, context: Context) {
    let state = $isOpen
    view.updateTrigger(open: isOpen && context.environment.isEnabled, show: {
      view.present(items(), width: width, prefersSelection: prefersSelection,
        trailing: trailing, dismissTree: dismissTree, didClose: { state.wrappedValue = false })
    })
  }

  static func dismantleNSView(_ view: CossMenuAnchorView, coordinator: ()) { view.dismiss() }
}

private struct CossContextMenuAnchor: NSViewRepresentable {
  @Binding var isOpen: Bool
  let items: () -> [CossMenuItem]

  func makeNSView(context: Context) -> CossMenuAnchorView { CossMenuAnchorView() }

  func updateNSView(_ view: CossMenuAnchorView, context: Context) {
    view.contextItems = context.environment.isEnabled ? items : nil
    CossContextMenus.register(view)
    let state = $isOpen
    view.updateTrigger(open: isOpen && context.environment.isEnabled, show: {
      view.present(items(), width: 216, didClose: { state.wrappedValue = false })
    }, dismissOnClose: false)
  }

  static func dismantleNSView(_ view: CossMenuAnchorView, coordinator: ()) {
    CossContextMenus.unregister(view)
    view.dismiss()
  }
}

private struct CossContextMenu: ViewModifier {
  let items: () -> [CossMenuItem]
  @ViewState private var isOpen = false

  func body(content: Content) -> some View {
    content
      .background { CossContextMenuAnchor(isOpen: $isOpen, items: items) }
      .accessibilityAction(named: Text("更多操作")) { if !items().isEmpty { isOpen = true } }
  }
}

extension View {
  func cossContextMenu(@CossMenuItems items: @escaping () -> [CossMenuItem]) -> some View {
    modifier(CossContextMenu(items: items))
  }
}

@MainActor private enum CossContextMenus {
  private static let anchors = NSHashTable<CossMenuAnchorView>.weakObjects()
  private static var monitor: Any?

  static func register(_ anchor: CossMenuAnchorView) {
    anchors.add(anchor)
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
          let window = event.window else { return false }
        for view in anchors.allObjects where view.window === window && !view.isHiddenOrHasHiddenAncestor {
          let point = view.convert(event.locationInWindow, from: nil)
          if view.visibleRect.contains(point), let items = view.contextItems?(), !items.isEmpty {
            view.present(items, width: 216, point: window.convertPoint(toScreen: event.locationInWindow))
            return true
          }
        }
        return false
      }
      return handled ? nil : event
    }
  }

  static func unregister(_ anchor: CossMenuAnchorView) {
    anchors.remove(anchor)
    if anchors.allObjects.isEmpty, let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}

/// The panel is a child window, so menus escape scroll clipping and fit inside the current screen.
@MainActor final class CossMenuAnchorView: NSView {
  private static weak var activeRoot: CossMenuAnchorView?
  var contextItems: (() -> [CossMenuItem])?
  private var popup: CossMenuWindow?
  private var popoverHost: CossPopoverHost?
  private var monitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var didClose: (() -> Void)?
  private var pendingPresentation: (() -> Void)?
  private weak var previousResponder: NSResponder?

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func updateTrigger(open: Bool, show: @escaping () -> Void, dismissOnClose: Bool = true) {
    pendingPresentation = open && popup == nil ? show : nil
    if open && popup == nil {
      DispatchQueue.main.async { [weak self] in
        let pending = self?.pendingPresentation
        self?.pendingPresentation = nil
        pending?()
      }
    } else if !open && dismissOnClose {
      dismiss()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { dismiss() }
  }

  func present(
    _ items: [CossMenuItem], width: CGFloat, prefersSelection: Bool = false, trailing: Bool = false,
    point: NSPoint? = nil, dismissTree: (() -> Void)? = nil, didClose: (() -> Void)? = nil
  ) {
    guard popup == nil, !items.isEmpty, let parent = window,
      let screen = parent.screen ?? NSScreen.main else { return }
    if dismissTree == nil {
      Self.activeRoot?.dismiss(restoreFocus: false)
      Self.activeRoot = self
    }
    let target = parent.convertToScreen(convert(bounds, to: nil))
    let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
    let panelWidth = min(visible.width, max(width, trailing || point != nil ? 0 : target.width))
    let height = min(visible.height, CossMenuPanel.maximumHeight, CossMenuPanel.contentHeight(items))
    let gap: CGFloat = 4
    let x: CGFloat
    let y: CGFloat
    if let point {
      x = point.x
      y = point.y - height
    } else if trailing {
      x = target.maxX + panelWidth + gap <= visible.maxX
        ? target.maxX + gap : target.minX - panelWidth - gap
      y = target.maxY - height
    } else {
      x = target.minX
      y = target.minY - height - gap >= visible.minY || visible.maxY - target.maxY < target.minY - visible.minY
        ? target.minY - height - gap : target.maxY + gap
    }
    let frame = NSRect(x: min(visible.maxX - panelWidth, max(visible.minX, x)),
      y: min(visible.maxY - height, max(visible.minY, y)), width: panelWidth, height: height)
    let controller = NSHostingController(rootView: CossMenuPanel(items: items,
      width: panelWidth, height: height, prefersSelection: prefersSelection, isSubmenu: trailing,
      dismiss: { [weak self] in self?.dismiss() },
      dismissTree: dismissTree ?? { [weak self] in self?.dismiss() }))
    showPanel(controller, frame: frame, parent: parent, isMenu: true, didClose: didClose)
  }

  func updatePopover(content: AnyView, edge: Edge, alignment: HorizontalAlignment, didClose: @escaping () -> Void) {
    if let popoverHost {
      popoverHost.rootView = content
      return
    }
    updateTrigger(open: true, show: { [weak self] in
      guard let self, let parent = self.window else { return }
      let host = CossPopoverHost(rootView: content)
      guard let frame = self.popoverFrame(size: host.view.fittingSize, edge: edge, alignment: alignment) else { return }
      self.popoverHost = host
      host.onLayout = { [weak self] size in
        guard let self, let popup = self.popup, let frame = self.popoverFrame(size: size, edge: edge, alignment: alignment),
          popup.frame != frame else { return }
        popup.setFrame(frame, display: true)
      }
      self.showPanel(host, frame: frame, parent: parent, isMenu: false, didClose: didClose)
    })
  }

  private func popoverFrame(size: NSSize, edge: Edge, alignment: HorizontalAlignment) -> NSRect? {
    guard let parent = window, let screen = parent.screen ?? NSScreen.main else { return nil }
    let target = parent.convertToScreen(convert(bounds, to: nil))
    let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    let width = min(size.width, visible.width)
    let height = min(size.height, visible.height)
    let offset: CGFloat = 6
    let x: CGFloat
    let y: CGFloat
    switch edge {
    case .leading, .trailing:
      let left = target.minX - width - offset
      let right = target.maxX + offset
      x = edge == .leading && left >= visible.minX || right + width > visible.maxX ? left : right
      y = target.midY - height / 2
    case .bottom, .top:
      let below = target.minY - height - offset
      let above = target.maxY + offset
      if alignment == .trailing { x = target.maxX - width }
      else if alignment == .leading { x = target.minX }
      else { x = target.midX - width / 2 }
      y = edge == .top && above + height <= visible.maxY || below < visible.minY ? above : below
    }
    return NSRect(x: max(visible.minX, min(visible.maxX - width, x)),
      y: max(visible.minY, min(visible.maxY - height, y)), width: width, height: height)
  }

  private func showPanel(
    _ controller: NSViewController, frame: NSRect, parent: NSWindow,
    isMenu: Bool, didClose: (() -> Void)?
  ) {
    let panel = CossMenuWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.contentViewController = controller
    popup = panel
    self.didClose = didClose
    previousResponder = parent.firstResponder
    parent.addChildWindow(panel, ordered: .above)
    panel.setFrame(frame, display: true)
    panel.makeKeyAndOrderFront(nil)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) {
      [weak self, weak panel] event in
      let handled = MainActor.assumeIsolated { () -> Bool in
        if event.type == .keyDown {
          if isMenu && event.window === panel && event.keyCode == 53 {
            self?.dismiss()
            return true
          }
          return false
        }
        if !isMenu && event.window is NSColorPanel { return false }
        var window = event.window
        while let candidate = window {
          if candidate === panel { return false }
          window = candidate.parent
        }
        self?.dismiss(restoreFocus: false)
        return false
      }
      return handled ? nil : event
    }
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
        [weak self] _ in MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
      },
      center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) {
        [weak self] _ in MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
      }
    ]
  }

  func dismiss(restoreFocus: Bool = true) {
    pendingPresentation = nil
    guard let panel = popup else { return }
    popup = nil
    popoverHost = nil
    if Self.activeRoot === self { Self.activeRoot = nil }
    let wasKey = panel.isKeyWindow || panel.childWindows?.contains(where: \.isKeyWindow) == true
    let parent = panel.parent
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers = []
    parent?.removeChildWindow(panel)
    panel.close()
    if restoreFocus, wasKey, NSApp.isActive, let parent {
      parent.makeKey()
      if let previousResponder { parent.makeFirstResponder(previousResponder) }
    }
    previousResponder = nil
    let callback = didClose
    didClose = nil
    if let callback { DispatchQueue.main.async { callback() } }
  }
}

private final class CossMenuWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private final class CossPopoverHost: NSHostingController<AnyView> {
  var onLayout: ((NSSize) -> Void)?
  private var lastSize = NSSize.zero

  override func viewDidLayout() {
    super.viewDidLayout()
    let size = view.fittingSize
    guard size != lastSize else { return }
    lastSize = size
    DispatchQueue.main.async { [weak self] in
      guard self?.lastSize == size else { return }
      self?.onLayout?(size)
    }
  }
}
