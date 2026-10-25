import AppKit
import BoxmailCore
import SwiftUI
import WebKit

struct HTMLMailBodyView: NSViewRepresentable {
  let html: String
  let fontSize: Int
  let allowRemoteImages: Bool
  @Binding var height: CGFloat
  var collapseQuotes = false
  var updatesTextOnly = false

  func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.userContentController.add(
      context.coordinator, contentWorld: .defaultClient, name: "mailBodyHeight")
    configuration.userContentController.add(
      context.coordinator, contentWorld: .defaultClient, name: "mailRecipientScrollRegions")
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: MailHTMLDocument.recipientLayoutScript + "\n" + """
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
    context.coordinator.webView = webView
    webView.navigationDelegate = context.coordinator
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.height = $height
    let layoutKey = "\(fontSize)-\(allowRemoteImages)-\(collapseQuotes)"
    guard html != context.coordinator.html || layoutKey != context.coordinator.layoutKey else { return }
    context.coordinator.html = html
    let document = MailHTMLDocument.make(
      html: html, fontSize: fontSize, allowRemoteImages: allowRemoteImages, collapseQuotes: collapseQuotes)
    guard document != context.coordinator.document else { return }
    context.coordinator.update(document, layoutKey: layoutKey, textOnly: updatesTextOnly)
  }

  static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.stopLoading()
    (webView as? MailBodyWebView)?.stopForwardingScrollEvents()
    webView.navigationDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mailBodyHeight", contentWorld: .defaultClient)
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mailRecipientScrollRegions", contentWorld: .defaultClient)
  }

  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var height: Binding<CGFloat>
    var html: String?
    var document = ""
    var renderedDocument = ""
    var layoutKey = ""
    var renderedLayoutKey = ""
    var loading = false
    var updating = false
    var textOnly = false
    fileprivate weak var webView: MailBodyWebView?
    init(height: Binding<CGFloat>) { self.height = height }

    func update(_ next: String, layoutKey: String, textOnly: Bool) {
      document = next
      self.textOnly = textOnly
      self.layoutKey = layoutKey
      render()
    }

    private func render() {
      guard let webView, !loading, !updating, renderedDocument != document else { return }
      let next = document
      guard textOnly, renderedLayoutKey == layoutKey, !renderedDocument.isEmpty else { load(next); return }
      updating = true
      Task { @MainActor [weak self] in
        guard let self else { return }
        let patched = try? await webView.callAsyncJavaScript(MailHTMLDocument.textUpdatesScript,
          arguments: ["previousDocument": self.renderedDocument, "nextDocument": next],
          in: nil, contentWorld: .defaultClient)
        self.updating = false
        if patched as? Bool == true {
          self.renderedDocument = next
          self.render()
        } else { self.load(self.document) }
      }
    }

    private func load(_ next: String) {
      loading = true
      webView?.recipientRegions = []
      renderedDocument = next
      renderedLayoutKey = layoutKey
      webView?.loadHTMLString(next, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      loading = false
      render()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      loading = false
      updating = false
      renderedDocument = ""
      render()
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      if message.name == "mailRecipientScrollRegions", message.frameInfo.isMainFrame,
        let regions = message.body as? [[String: Double]]
      {
        webView?.recipientRegions = regions
        return
      }
      guard message.frameInfo.isMainFrame, let value = message.body as? NSNumber else { return }
      let next = max(1, min(100_000, CGFloat(value.doubleValue)))
      guard next.isFinite else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, abs(self.height.wrappedValue - next) > 1 else { return }
        self.height.wrappedValue = next
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      if navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url, MailHTMLDocument.externalLink(url)
      {
        NSWorkspace.shared.open(url)
      }
      decisionHandler(
        navigationAction.navigationType == .other
          && navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
  }
}

struct MailBodyView: View {
  let message: MailMessage
  let preferences: Preferences
  var collapseQuotes = false
  var updatesTextOnly = false
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
        HTMLMailBodyView(
          html: html, fontSize: preferences.fontSize,
          allowRemoteImages: !preferences.blockRemoteImages || loadRemoteImages, height: $height,
          collapseQuotes: collapseQuotes, updatesTextOnly: updatesTextOnly
        )
        .frame(height: height)
      }.frame(maxWidth: .infinity, alignment: .leading)
    } else {
      let visible = collapseQuotes ? QuotedMailText.split(message.body).visible : message.body
      Text(visible.isEmpty ? "这封邮件没有可展示的正文，或正文仅包含引用内容。" : visible)
        .font(.system(size: CGFloat(preferences.fontSize))).lineSpacing(7).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true).frame(
          maxWidth: .infinity, alignment: .leading)
    }
  }
}
