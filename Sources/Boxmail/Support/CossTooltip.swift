import AppKit
import SwiftUI

struct CossControlFocusKey: PreferenceKey {
  static var defaultValue = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
  func cossTooltip(_ text: String) -> some View { modifier(CossTooltip(text: text)) }
}

private struct CossTooltip: ViewModifier {
  let text: String
  @ViewState private var hovered = false
  @ViewState private var focused = false
  @ViewState private var visible = false
  @Environment(\.isEnabled) private var enabled

  private var eligible: Bool { enabled && !text.isEmpty && (hovered || focused) }

  func body(content: Content) -> some View {
    content.onHover { hovered = $0 }
      .onPreferenceChange(CossControlFocusKey.self) { focused = $0 }
      .transformPreference(CossControlFocusKey.self) { $0 = false }
      .background { CossTooltipAnchor(text: text, visible: visible && eligible) }
      .accessibilityHint(text)
      .task(id: eligible) {
        visible = false
        if eligible {
          try? await Task.sleep(for: .milliseconds(450))
          if !Task.isCancelled { visible = true }
        }
      }
  }
}

private struct CossTooltipAnchor: NSViewRepresentable {
  let text: String
  let visible: Bool

  func makeNSView(context: Context) -> AnchorView { AnchorView() }

  func updateNSView(_ view: AnchorView, context: Context) {
    if visible {
      view.show(text)
    } else {
      view.hide()
    }
  }

  static func dismantleNSView(_ view: AnchorView, coordinator: ()) { view.hide() }

  @MainActor final class AnchorView: NSView {
    private static weak var visibleAnchor: AnchorView?
    private var panel: CossTooltipPanel?
    private var renderedText: String?
    private var resignObserver: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { hide() }
    }

    func show(_ text: String) {
      guard let parent = window, parent.isKeyWindow, let screen = parent.screen else { return }
      if renderedText == text, panel != nil { return }
      Self.visibleAnchor?.hide()
      Self.visibleAnchor = self
      let shape = RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous)
      let content = Text(text).font(UIType.small).foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: 320)
        .background(Palette.paper, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
      let host = NSHostingView(rootView: content)
      let size = host.fittingSize
      let target = parent.convertToScreen(convert(bounds, to: nil))
      let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
      let top = target.maxY + 6
      let origin = NSPoint(x: min(visible.maxX - size.width, max(visible.minX, target.midX - size.width / 2)),
        y: top + size.height <= visible.maxY ? top : target.minY - size.height - 6)
      let popup = CossTooltipPanel(contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      popup.isReleasedWhenClosed = false
      popup.isOpaque = false
      popup.hasShadow = true
      popup.backgroundColor = .clear
      popup.ignoresMouseEvents = true
      popup.hidesOnDeactivate = true
      popup.collectionBehavior = [.transient, .ignoresCycle]
      popup.setAccessibilityHidden(true)
      popup.contentView = host
      parent.addChildWindow(popup, ordered: .above)
      popup.orderFront(nil)
      resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
        object: parent, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
      panel = popup
      renderedText = text
    }

    func hide() {
      if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
      resignObserver = nil
      if let panel {
        panel.parent?.removeChildWindow(panel)
        panel.close()
      }
      panel = nil
      renderedText = nil
      if Self.visibleAnchor === self { Self.visibleAnchor = nil }
    }
  }
}

private final class CossTooltipPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
