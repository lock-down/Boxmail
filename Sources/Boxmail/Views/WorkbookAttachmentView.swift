import SwiftUI
import WebKit

struct WorkbookAttachmentView: NSViewRepresentable {
  let html: String
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config)
    view.navigationDelegate = context.coordinator
    return view
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    guard context.coordinator.loadedHTML != html else { return }
    context.coordinator.loadedHTML = html
    view.loadHTMLString(html, baseURL: nil)
  }
  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.navigationDelegate = nil
  }
  final class Coordinator: NSObject, WKNavigationDelegate {
    var loadedHTML: String?
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      decisionHandler(
        action.navigationType == .other && action.request.url?.absoluteString == "about:blank"
          ? .allow : .cancel)
    }
  }
}
