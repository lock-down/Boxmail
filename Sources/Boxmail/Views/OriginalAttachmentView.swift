import AppKit
import PDFKit
import Quartz
import SwiftUI

struct OriginalAttachmentView: View {
  let url: URL
  let isPDF: Bool
  let contentType: String

  static func isMarkdown(name: String, contentType: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    let mime = contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
    return ["md", "markdown"].contains(ext) || mime?.lowercased() == "text/markdown"
  }

  var body: some View {
    if Self.isMarkdown(name: url.lastPathComponent, contentType: contentType) {
      MarkdownAttachmentPreview(url: url)
    } else {
      SystemAttachmentPreview(url: url, isPDF: isPDF)
    }
  }
}

/// SwiftUI owns the file URL. The native views own only the rendering lifecycle.
struct SystemAttachmentPreview: NSViewRepresentable {
  let url: URL
  let isPDF: Bool

  func makeNSView(context: Context) -> NSView {
    if isPDF {
      let view = PDFView()
      view.autoScales = true
      view.displayMode = .singlePageContinuous
      view.displayDirection = .vertical
      view.backgroundColor = .windowBackgroundColor
      return view
    }
    let view = QLPreviewView(frame: .zero, style: .normal)!
    view.shouldCloseWithWindow = false
    view.autostarts = false
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if let view = nsView as? PDFView {
      if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    } else if let view = nsView as? QLPreviewView {
      if view.previewItem?.previewItemURL != url { view.previewItem = url as NSURL }
    }
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
    if let view = nsView as? QLPreviewView {
      view.previewItem = nil
      view.close()
    }
    if let view = nsView as? PDFView { view.document = nil }
  }
}
