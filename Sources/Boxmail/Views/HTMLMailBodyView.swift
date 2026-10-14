import AppKit
import BoxmailCore
import SwiftUI
import WebKit

struct HTMLMailBodyView: NSViewRepresentable {
  let html: String
  let fontSize: Int
  let allowRemoteImages: Bool
  @Binding var height: CGFloat

  func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.userContentController.add(
      context.coordinator, contentWorld: .defaultClient, name: "mailBodyHeight")
    configuration.userContentController.addUserScript(WKUserScript(
      source: """
        const content = document.getElementById('mail-content');
        if (content) {
          const report = () => window.webkit.messageHandlers.mailBodyHeight.postMessage(
            Math.ceil(Math.max(content.getBoundingClientRect().height, content.scrollHeight)));
          new ResizeObserver(report).observe(content);
          report();
        }
        """,
      injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
    let webView = MailBodyWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.height = $height
    let document = MailHTMLDocument.make(
      html: html, fontSize: fontSize, allowRemoteImages: allowRemoteImages)
    guard document != context.coordinator.document else { return }
    context.coordinator.document = document
    webView.loadHTMLString(document, baseURL: nil)
  }

  static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.stopLoading()
    (webView as? MailBodyWebView)?.stopForwardingScrollEvents()
    webView.navigationDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mailBodyHeight", contentWorld: .defaultClient)
  }

  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var height: Binding<CGFloat>
    var document = ""
    init(height: Binding<CGFloat>) { self.height = height }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard message.frameInfo.isMainFrame, let value = message.body as? NSNumber else { return }
      let next = max(1, min(100_000, CGFloat(value.doubleValue)))
      guard next.isFinite else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, abs(self.height.wrappedValue - next) > 1 else { return }
        self.height.wrappedValue = next
      }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      if navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url, MailHTMLDocument.externalLink(url) {
        NSWorkspace.shared.open(url)
      }
      decisionHandler(navigationAction.navigationType == .other
        && navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
  }
}

// HTML is sized to its content. The enclosing SwiftUI scroll view owns vertical scrolling.
private final class MailBodyWebView: WKWebView {
  private var scrollMonitor: Any?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stopForwardingScrollEvents()
    guard window != nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self else { return event }
      guard event.window === self.window,
        self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
        let scrollView = self.parentScrollView else { return event }
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

struct MailBodyView: View {
  let message: MailMessage
  let preferences: Preferences
  @ViewState<CGFloat> private var height: CGFloat = 240
  @ViewState<Bool> private var loadRemoteImages = false

  var body: some View {
    if let html = message.html, !html.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        if message.hasRemoteImages == true && preferences.blockRemoteImages && !loadRemoteImages {
          HStack(spacing: 10) {
            Text("此邮件包含外部图片").font(.system(size: 11)).foregroundStyle(Palette.muted)
            ActionButton(title: "加载本封邮件图片") { loadRemoteImages = true }
          }
        }
        HTMLMailBodyView(html: html, fontSize: preferences.fontSize,
          allowRemoteImages: !preferences.blockRemoteImages || loadRemoteImages, height: $height)
          .frame(height: height)
      }.frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(message.body.isEmpty ? "这封邮件没有可展示的正文。" : message.body)
        .font(.system(size: CGFloat(preferences.fontSize))).lineSpacing(7).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
