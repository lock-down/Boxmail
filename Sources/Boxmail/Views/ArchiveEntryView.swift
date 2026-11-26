import AppKit
import BoxmailCore
import SwiftUI

struct ArchiveEntryView: View {
  let attachmentId: String
  let entry: ArchiveEntry
  @ViewState<String> private var tab = "原文件"
  @ViewState<AttachmentPreviewFile?> private var file: AttachmentPreviewFile?
  @ViewState<URL?> private var documentURL: URL?
  @ViewState<Bool> private var loading = false
  @ViewState<String?> private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text(entry.path).font(UIType.section).lineLimit(2).truncationMode(.middle).cossTooltip(entry.path)
          .textSelection(.enabled)
        HStack {
          if entry.analysis?.isEmpty == false {
            FilterBar(values: ["原文件", "历史分析"], selection: $tab, compact: true)
          }
          Spacer()
          if let file {
            ActionButton(title: "打开文件", icon: .externalLink) {
              NSWorkspace.shared.open(file.url)
            }
          }
        }
      }.padding(16)
      CossSeparator()
      if tab == "历史分析", let analysis = entry.analysis {
        OverlayScrollView { AnalysisDocumentView(text: analysis).padding(20) }
      } else if let file {
        if let documentURL {
          SandboxedWebPreview(source: .file(documentURL))
        } else {
          OriginalAttachmentView(url: file.url, isPDF: entry.contentType == "application/pdf", contentType: entry.contentType)
        }
      } else if loading {
        CossSpinner(label: "正在读取包内文件…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        EmptyState(title: "暂时无法预览", subtitle: error ?? entry.error ?? "此文件暂不支持预览。", icon: .file)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.task(id: "\(entry.id)-\(tab)") {
      guard tab == "原文件", file == nil, entry.canPreview else { return }
      loading = true
      defer { loading = false }
      do {
        let loaded = try await AttachmentPreviewLoader.load(
          path: "/attachments/\(attachmentId)/archive/\(entry.id)",
          isPDF: entry.contentType == "application/pdf",
          isWord: AttachmentKind(name: entry.name, contentType: entry.contentType) == .word)
        try Task.checkCancellation()
        documentURL = loaded.documentURL
        file = loaded.file
      } catch is CancellationError {
      } catch { self.error = error.localizedDescription }
    }.onDisappear {
      file?.remove()
      file = nil
      documentURL = nil
    }
  }
}
