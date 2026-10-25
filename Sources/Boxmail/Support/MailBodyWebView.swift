import AppKit
import WebKit

// HTML is sized to its content. The enclosing SwiftUI scroll view owns vertical scrolling.
final class MailBodyWebView: WKWebView {
  private var scrollMonitor: Any?
  var recipientRegions: [[String: Double]] = [] {
    didSet { updateRecipientScrollers() }
  }
  private var recipientScrollers: [NSScroller] = []

  override func layout() {
    super.layout()
    updateRecipientScrollers()
  }

  private func updateRecipientScrollers() {
    while recipientScrollers.count > recipientRegions.count {
      recipientScrollers.removeLast().removeFromSuperview()
    }
    for (index, region) in recipientRegions.enumerated() {
      if index == recipientScrollers.count {
        let scroller = BorderlessOverlayScroller()
        scroller.scrollerStyle = .legacy
        scroller.controlSize = .small
        scroller.isContinuous = true
        scroller.target = self
        scroller.action = #selector(scrollRecipients(_:))
        scroller.setAccessibilityLabel("引用邮件的收件人滚动条")
        addSubview(scroller)
        recipientScrollers.append(scroller)
      }
      let scroller = recipientScrollers[index]
      let width = region["width"] ?? 0, height = region["height"] ?? 0
      let visible = region["visible"] ?? 0, total = region["total"] ?? 0
      let top = region["top"] ?? 0
      let rect = NSRect(x: region["x"] ?? 0, y: region["y"] ?? 0, width: width, height: height)
      guard [rect.minX, rect.minY, rect.width, rect.height, visible, total, top].allSatisfy({ $0.isFinite }),
        width > 14, height > 0, visible > 0, total > visible else {
        scroller.isHidden = true
        continue
      }
      scroller.isHidden = false
      scroller.isEnabled = true
      let frame = NSRect(x: rect.maxX - 14,
        y: isFlipped ? rect.minY : bounds.height - rect.maxY, width: 14, height: rect.height)
      if scroller.frame != frame { scroller.frame = frame }
      scroller.knobProportion = CGFloat(min(1, visible / total))
      scroller.doubleValue = min(1, max(0, top / (total - visible)))
      scroller.needsDisplay = true
    }
  }

  @objc private func scrollRecipients(_ sender: NSScroller) {
    guard let index = recipientScrollers.firstIndex(where: { $0 === sender }),
      recipientRegions.indices.contains(index) else { return }
    let region = recipientRegions[index]
    let visible = region["visible"] ?? 0
    let maximum = max(0, (region["total"] ?? 0) - visible)
    let current = region["top"] ?? 0
    let next: Double
    switch sender.hitPart {
    case .incrementLine: next = current + 24
    case .decrementLine: next = current - 24
    case .incrementPage: next = current + visible * 0.9
    case .decrementPage: next = current - visible * 0.9
    default: next = sender.doubleValue * maximum
    }
    Task { @MainActor [weak self] in
      _ = try? await self?.callAsyncJavaScript("""
        const list = document.querySelectorAll('#mail-content .boxmail-recipient-list')[index];
        if (list) list.scrollTop = top;
        """, arguments: ["index": index, "top": min(maximum, max(0, next))],
        in: nil, contentWorld: .defaultClient)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stopForwardingScrollEvents()
    guard window != nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self else { return event }
      guard event.window === self.window,
        self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
        let scrollView = self.parentScrollView
      else { return event }
      let point = self.convert(event.locationInWindow, from: nil)
      let location = NSPoint(x: point.x, y: self.isFlipped ? point.y : self.bounds.height - point.y)
      for region in self.recipientRegions {
        let rect = NSRect(
          x: region["x"] ?? 0, y: region["y"] ?? 0,
          width: region["width"] ?? 0, height: region["height"] ?? 0)
        guard rect.contains(location) else { continue }
        let top = region["top"] ?? 0
        let remaining = (region["total"] ?? 0) - (region["visible"] ?? 0) - top
        if (event.scrollingDeltaY > 0 && top > 1) || (event.scrollingDeltaY < 0 && remaining > 1) {
          return event
        }
      }
      scrollView.scrollWheel(with: event)
      return nil
    }
  }

  func stopForwardingScrollEvents() {
    if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    scrollMonitor = nil
  }

  private var parentScrollView: NSScrollView? {
    var ancestor = superview
    while let view = ancestor {
      if let scrollView = view as? NSScrollView { return scrollView }
      ancestor = view.superview
    }
    return nil
  }
}

