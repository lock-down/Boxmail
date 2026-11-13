import AppKit
import SwiftUI

struct RecipientAddressList: NSViewRepresentable {
  let fields: [RecipientField]

  func makeNSView(context: Context) -> RecipientScrollView { RecipientScrollView() }
  func updateNSView(_ view: RecipientScrollView, context: Context) {
    view.setFields(fields)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecipientScrollView, context: Context) -> CGSize? {
    guard let width = proposal.width else { return nil }
    return CGSize(width: width, height: min(240, max(36, nsView.textHeight(width: width))))
  }
  static func dismantleNSView(_ view: RecipientScrollView, coordinator: ()) { view.stopMonitoring() }
}

/// Own wheel events inside the bounded address list; hand off to the page only at an edge.
final class RecipientScrollView: NSScrollView {
  let addresses = NSTextView()
  private var fields: [RecipientField] = []
  private var scrollMonitor: Any?

  init() {
    super.init(frame: .zero)
    hasVerticalScroller = true
    verticalScrollElasticity = .none
    addresses.isEditable = false
    addresses.isSelectable = true
    addresses.drawsBackground = false
    addresses.isVerticallyResizable = true
    addresses.isHorizontallyResizable = false
    addresses.minSize = .zero
    addresses.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    addresses.autoresizingMask = [.width]
    addresses.textContainerInset = NSSize(width: 12, height: 12)
    addresses.textContainer?.lineFragmentPadding = 0
    addresses.textContainer?.widthTracksTextView = true
    documentView = addresses
    ScrollAppearance.apply(to: self, persistentIndicators: true)
    setAccessibilityLabel("收件信息名单")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setFields(_ next: [RecipientField]) {
    guard fields != next else { return }
    fields = next
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    let text = NSMutableAttributedString()
    for field in fields {
      if text.length > 0 { text.append(NSAttributedString(string: "\n\n")) }
      text.append(NSAttributedString(string: field.title + "\n", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(Palette.muted),
      ]))
      text.append(NSAttributedString(string: field.value, attributes: [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(Palette.ink),
      ]))
    }
    text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
    addresses.textStorage?.setAttributedString(text)
    needsLayout = true
    invalidateIntrinsicContentSize()
  }

  func textHeight(width: CGFloat) -> CGFloat {
    let gutter = NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy)
    let size = NSSize(width: max(1, width - gutter - 24), height: CGFloat.greatestFiniteMagnitude)
    return ceil(addresses.attributedString().boundingRect(with: size,
      options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 24
  }

  override func layout() {
    super.layout()
    let height = textHeight(width: bounds.width)
    addresses.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: max(contentSize.height, height))
  }

  override func scrollWheel(with event: NSEvent) {
    guard ScrollEventRouting.containsPointer(in: self) else {
      ScrollEventRouting.parentScrollView(of: self)?.scrollWheel(with: event)
      return
    }
    let top = contentView.bounds.minY
    let bottom = max(0, addresses.bounds.height - contentView.bounds.height)
    if (event.scrollingDeltaY > 0 && top > 0) || (event.scrollingDeltaY < 0 && top < bottom) {
      let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : verticalLineScroll)
      contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: min(bottom, max(0, top - delta))))
      reflectScrolledClipView(contentView)
    } else {
      ScrollEventRouting.parentScrollView(of: self)?.scrollWheel(with: event)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stopMonitoring()
    guard window != nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, event.window === self.window,
        ScrollEventRouting.containsPointer(in: self) else { return event }
      self.scrollWheel(with: event)
      return nil
    }
  }

  func stopMonitoring() {
    if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    scrollMonitor = nil
  }

  static func containsList(in root: NSView) -> Bool {
    if let list = root as? RecipientScrollView, ScrollEventRouting.containsPointer(in: list) { return true }
    return root.subviews.contains { containsList(in: $0) }
  }
}
