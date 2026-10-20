import AppKit
import PDFKit
import WebKit

// Render the system's Office preview offscreen, one PDF page per slide.
// This executable has no window and never opens the original file in an Office app.
private struct PreviewFailure: Error {
  let message: String
}

private final class PresentationRenderer: NSObject, WKNavigationDelegate {
  private let view: WKWebView
  private let input: URL
  private let output: URL
  private let expectedPages: Int
  private let pageLimit: Int
  private var finished = false

  init(input: URL, output: URL, expectedPages: Int, pageLimit: Int) {
    self.input = input
    self.output = output
    self.expectedPages = expectedPages
    self.pageLimit = pageLimit
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000), configuration: configuration)
    super.init()
    view.navigationDelegate = self
  }

  func start() {
    let rules = #"[{"trigger":{"url-filter":"^[a-zA-Z][a-zA-Z0-9+.-]*:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}]"#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "BoxmailLocalPresentation", encodedContentRuleList: rules) { [self] list, error in
      guard let list, error == nil else { fail("PPT 页面渲染未能启动，请重试或转换为 PDF 后理解。"); return }
      view.configuration.userContentController.add(list)
      view.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = navigationAction.request.url
    decisionHandler(url == input || url?.absoluteString == "about:blank" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      do {
        let raw = try await view.callAsyncJavaScript("""
          await document.fonts.ready;
          const images = Array.from(document.images);
          await Promise.all(images.map(image => image.complete ? Promise.resolve() :
            new Promise(resolve => { image.onload = resolve; image.onerror = resolve; })));
          if (images.some(image => !image.naturalWidth) || document.querySelector('.loading-slide'))
            return { incomplete: true, frames: [] };
          return { incomplete: false, frames: Array.from(document.querySelectorAll('div.slide')).map(element => {
            const rect = element.getBoundingClientRect();
            return [rect.x + window.scrollX, rect.y + window.scrollY, rect.width, rect.height];
          }) };
          """, arguments: [:], in: nil, contentWorld: .page)
        guard let result = raw as? [String: Any], result["incomplete"] as? Bool == false,
          let frames = result["frames"] as? [[Double]], !frames.isEmpty else {
          throw PreviewFailure(message: "PPT 页面未能完整读取，请转换为 PDF 后理解。")
        }
        if expectedPages > 0 && frames.count != expectedPages {
          throw PreviewFailure(message: "PPT 页面数量与原文件不一致，请转换为 PDF 后理解。")
        }
        if frames.count > pageLimit {
          throw PreviewFailure(message: "PPT 共 \(frames.count) 页，请拆分为每份不超过 \(pageLimit) 页后解析")
        }
        let document = PDFDocument()
        for frame in frames {
          guard frame.count == 4, frame.allSatisfy(\.isFinite), frame[0] >= 0, frame[1] >= 0,
            (10...20000).contains(frame[2]), (10...20000).contains(frame[3]) else {
            throw PreviewFailure(message: "PPT 页面尺寸无效，请转换为 PDF 后理解。")
          }
          let configuration = WKPDFConfiguration()
          configuration.rect = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
          let data = try await view.pdf(configuration: configuration)
          guard let pdf = PDFDocument(data: data), pdf.pageCount == 1, let page = pdf.page(at: 0) else {
            throw PreviewFailure(message: "PPT 页面无法转换，请检查文件。")
          }
          document.insert(page, at: document.pageCount)
        }
        guard document.write(to: output) else { throw PreviewFailure(message: "PPT 临时页面无法保存，请重试。") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        finish(["pages": document.pageCount], code: 0)
      } catch {
        fail((error as? PreviewFailure)?.message ?? "PPT 页面渲染失败，请转换为 PDF 后理解。")
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    fail("PPT 页面加载失败，请重试或转换为 PDF 后理解。")
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    fail("PPT 页面加载失败，请重试或转换为 PDF 后理解。")
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    fail("PPT 页面渲染已中断，请重试或拆分文稿。")
  }
  private func fail(_ message: String) { finish(["error": message], code: 1) }
  private func finish(_ result: [String: Any], code: Int32) {
    guard !finished else { return }
    finished = true
    if let data = try? JSONSerialization.data(withJSONObject: result) {
      FileHandle.standardOutput.write(data)
    }
    exit(code)
  }
}

guard CommandLine.arguments.count == 5,
  let expectedPages = Int(CommandLine.arguments[3]), let pageLimit = Int(CommandLine.arguments[4]),
  expectedPages >= 0, pageLimit > 0 else { exit(2) }
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
private let renderer = PresentationRenderer(
  input: URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL,
  output: URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL, expectedPages: expectedPages, pageLimit: pageLimit)
renderer.start()
application.run()
