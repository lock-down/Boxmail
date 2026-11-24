import BoxmailCore
import SwiftUI

struct MarkdownAttachmentPreview: View {
  let url: URL
  @ViewState<[AnalysisBlock]?> private var blocks = nil
  @ViewState<Bool> private var useSystemPreview = false

  var body: some View {
    Group {
      if let blocks {
        OverlayScrollView {
          AnalysisDocumentView(blocks: blocks).padding(24)
        }
      } else if useSystemPreview {
        SystemAttachmentPreview(url: url, isPDF: false)
      } else {
        CossSpinner(label: "正在读取 Markdown…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.task(id: url) {
      blocks = nil
      useSystemPreview = false
      let worker = Task.detached(priority: .userInitiated) { [url] in
        var encoding = String.Encoding.utf8
        let source = try String(contentsOf: url, usedEncoding: &encoding)
        try Task.checkCancellation()
        return AnalysisDocument.blocks(source, interpretLegacyOutline: false)
      }
      do {
        let rendered = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        if !Task.isCancelled { blocks = rendered }
      } catch {
        if !Task.isCancelled { useSystemPreview = true }
      }
    }
  }
}
