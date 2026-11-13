import SwiftUI
import WebKit

struct SandboxedWebPreview: NSViewRepresentable {
  enum Source: Equatable {
    case file(URL)
    case html(String)
  }

  let source: Source

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    if case .file = source { view.setAccessibilityLabel("附件原文件预览") }
    return view
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.update(source, in: view)
  }
  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.navigationDelegate = nil
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    private var source: Source?
    func update(_ next: Source, in view: WKWebView) {
      guard source != next else { return }
      source = next
      switch next {
      case .file(let url): view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      case .html(let html): view.loadHTMLString(html, baseURL: nil)
      }
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      let allowed: Bool
      switch source {
      case .file(let url):
        allowed = action.request.url == url && action.navigationType == .other
      case .html:
        allowed = action.navigationType == .other
          && action.request.url?.absoluteString == "about:blank"
      case nil:
        allowed = false
      }
      decisionHandler(allowed ? .allow : .cancel)
    }
  }
}
