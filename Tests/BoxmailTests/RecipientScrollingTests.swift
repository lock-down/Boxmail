import AppKit
import BoxmailCore
import SwiftUI
import Testing
import WebKit
@testable import Boxmail

@Suite(.serialized) @MainActor struct RecipientScrollingTests {
  @Test(arguments: [true, false])
  func overflowIndicatorsKeepTheirPolicyWhenWindowAppearanceRefreshes(persistent: Bool) {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
    scroll.hasVerticalScroller = true
    scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 1600))
    ScrollAppearance.apply(to: scroll, persistentIndicators: persistent)
    scroll.tile()
    ScrollAppearance.applyRecursively(to: scroll)
    scroll.tile()
    #expect(scroll.scrollerStyle == (persistent ? .legacy : .overlay))
    #expect(scroll.verticalScroller is BorderlessOverlayScroller)
    #expect(scroll.autohidesScrollers)
    if persistent {
      #expect(scroll.verticalScroller?.isHidden == false)
      #expect((scroll.verticalScroller?.knobProportion ?? 1) < 1)
    }
  }

  @Test(arguments: [false, true])
  func quotedRecipientsHaveAVisibleDraggableScrollbarInReadingAndForwardPreview(forwarding: Bool) async throws {
    let addresses = (1...100).map { "<a href='mailto:person\($0)@example.test'>Recipient \($0) &lt;person\($0)@example.test&gt;</a>" }.joined(separator: ", ")
    let html = "<table><tr><td style='width:1px;word-break:break-all'>收件人：</td><td>\(addresses)</td></tr></table><p>Body after recipients</p>"
    let content: AnyView = forwarding
      ? AnyView(ForwardedMailPreview(html: html, text: "Synthetic forward", preferences: Preferences()))
      : AnyView(HTMLMailBodyView(html: html, fontSize: 14, allowRemoteImages: false,
        height: .constant(600)).frame(height: 600))
    let host = NSHostingView(rootView: content.borderlessScrollers())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
    host.layoutSubtreeIfNeeded()
    defer { window.contentView = nil; window.close() }
    let deadline = Date().addingTimeInterval(15)
    var web: MailBodyWebView?
    while Date() < deadline {
      host.layoutSubtreeIfNeeded()
      web = findWebView(in: host)
      if let region = web?.recipientRegions.first, (region["total"] ?? 0) > (region["visible"] ?? 0) { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    let view = try #require(web)
    let region = try #require(view.recipientRegions.first)
    #expect((region["total"] ?? 0) > (region["visible"] ?? 0))
    let bar = try #require(view.subviews.compactMap { $0 as? BorderlessOverlayScroller }.first)
    #expect(!bar.isHidden && bar.isEnabled)
    #expect(bar.scrollerStyle == .legacy && bar.knobProportion < 1)
    bar.doubleValue = 0.75
    #expect(bar.sendAction(bar.action, to: bar.target))
    while Date() < deadline, (view.recipientRegions.first?["top"] ?? 0) < 1 {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect((view.recipientRegions.first?["top"] ?? 0) > 0)
    let tail = try await view.callAsyncJavaScript(
      "return document.querySelector('.boxmail-recipient-list').textContent.includes('person100@example.test');",
      arguments: [:], in: nil, contentWorld: .defaultClient)
    #expect(tail as? Bool == true)
    let labelMetrics = try await view.callAsyncJavaScript("""
      const label = document.querySelector('.boxmail-recipient-label');
      const text = document.createRange();
      text.selectNodeContents(label);
      const rect = text.getBoundingClientRect();
      return { width: rect.width, height: rect.height, whiteSpace: getComputedStyle(label).whiteSpace,
        verticalAlign: getComputedStyle(label).verticalAlign };
      """, arguments: [:], in: nil, contentWorld: .defaultClient)
    let metrics = try #require(labelMetrics as? [String: Any])
    #expect((metrics["width"] as? Double ?? 0) > (metrics["height"] as? Double ?? 0), Comment(rawValue: "\(metrics)"))
    #expect(metrics["whiteSpace"] as? String == "nowrap")
    #expect(metrics["verticalAlign"] as? String == "top")
    view.recipientRegions = []
    #expect(view.subviews.compactMap { $0 as? BorderlessOverlayScroller }.isEmpty)
  }

  private func findWebView(in root: NSView) -> MailBodyWebView? {
    if let web = root as? MailBodyWebView { return web }
    for child in root.subviews { if let web = findWebView(in: child) { return web } }
    return nil
  }
}
