import AppKit
import WebKit

// HTML is sized to its content. The enclosing SwiftUI scroll view owns vertical scrolling.
final class MailBodyWebView: WKWebView {
  private var scrollMonitor: Any?
  weak var recipients: MailRecipientState?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stopForwardingScrollEvents()
    guard window != nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self else { return event }
      guard event.window === self.window,
        ScrollEventRouting.containsPointer(in: self),
        let scrollView = ScrollEventRouting.parentScrollView(of: self)
      else { return event }
      if self.window?.contentView.map({ RecipientScrollView.containsList(in: $0) }) == true {
        return event
      }
      scrollView.scrollWheel(with: event)
      return nil
    }
  }

  func stopForwardingScrollEvents() {
    if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    scrollMonitor = nil
  }
}
