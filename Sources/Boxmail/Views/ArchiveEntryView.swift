import AppKit
import BoxmailCore
import SwiftUI

struct ArchiveEntryView: View {
  let attachmentId: String
  let entry: ArchiveEntry
  @ViewState<String> private var tab = "AI 理解"
  @ViewState<AttachmentPreviewFile?> private var file: AttachmentPreviewFile?
  @ViewState<URL?> private var documentURL: URL?
  @ViewState<Bool> private var loading = false
  @ViewState<String?> private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text(entry.path).font(UIType.section).lineLimit(2).truncationMode(.middle).help(entry.path)
          .textSelection(.enabled)
        HStack {
          FilterBar(values: ["AI 理解", "原文件"], selection: $tab, compact: true)
          Spacer()
          if let file {
            ActionButton(title: "打开文件", icon: "arrow.up.right.square") {
              NSWorkspace.shared.open(file.url)
            }
          }
        }
        if let reason = entry.error {
          Text(reason).font(UIType.caption).foregroundStyle(Palette.amber)
        }
      }.padding(16)
      Divider()
      if tab == "AI 理解" {
        OverlayScrollView {
          if let analysis = entry.analysis {
            AnalysisDocumentView(text: analysis).padding(20)
          } else {
            EmptyState(
              title: entry.status == "running" ? "正在理解这个文件" : "还没有单文件结果",
              subtitle: entry.error ?? "点击上方“理解压缩包”，逐个理解包内文件。", icon: "doc.text.magnifyingglass"
            )
            .frame(maxWidth: .infinity).padding(.top, 40)
          }
        }
      } else if let file {
        if let documentURL {
          DocumentAttachmentView(url: documentURL)
        } else {
          OriginalAttachmentView(url: file.url, isPDF: entry.contentType == "application/pdf")
        }
      } else if loading {
        ProgressView("正在读取包内文件…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        EmptyState(title: "暂时无法预览", subtitle: error ?? entry.error ?? "此文件暂不支持预览。", icon: "doc")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.task(id: "\(entry.id)-\(tab)") {
      guard tab == "原文件", file == nil, entry.canPreview else { return }
      loading = true
      defer { loading = false }
      do {
        let response: FileResponse = try await BackendService.shared.request(
          "/attachments/\(attachmentId)/archive/\(entry.id)")
        try Task.checkCancellation()
        let preview = try await AttachmentPreviewLoader.prepare(name: response.name, content: response.content,
          isPDF: entry.contentType == "application/pdf")
        var keep = false
        defer { if !keep { preview.remove() } }
        if AttachmentKind(name: entry.name, contentType: entry.contentType) == .word {
          documentURL = try await SystemDocumentPreview.prepare(preview)
        }
        try Task.checkCancellation()
        file = preview
        keep = true
      } catch is CancellationError {
      } catch { self.error = error.localizedDescription }
    }.onDisappear {
      file?.remove()
      file = nil
      documentURL = nil
    }
  }
}
