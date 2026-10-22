import SwiftUI
import WebKit

struct DocumentAttachmentView: NSViewRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.setAccessibilityLabel("附件原文件预览")
    return view
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    guard context.coordinator.url != url else { return }
    context.coordinator.url = url
    view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }
  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.navigationDelegate = nil
  }
  final class Coordinator: NSObject, WKNavigationDelegate {
    var url: URL?
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      decisionHandler(action.request.url == url && action.navigationType == .other ? .allow : .cancel)
    }
  }
}
