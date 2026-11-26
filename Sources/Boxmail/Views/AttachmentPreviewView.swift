import AppKit
import BoxmailCore
import PDFKit
import SwiftUI

struct AttachmentPreviewView: View {
  @Bindable var store: MailStore
  let attachmentId: String
  @Environment(\.dismiss) private var dismiss
  @ViewState<AttachmentPreviewFile?> private var previewFile: AttachmentPreviewFile?
  @ViewState<URL?> private var documentPreviewURL: URL?
  @ViewState<String?> private var workbookHTML: String?
  @ViewState<Bool> private var previewLoading = true
  @ViewState<String> private var previewError = ""
  @ViewState<String> private var tab = "原文件预览"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var currentId: String { store.attachmentPreviewIds.indices.contains(store.attachmentPreviewIndex) ? store.attachmentPreviewIds[store.attachmentPreviewIndex] : attachmentId }
  var attachment: MailAttachment? { store.attachments.first { $0.id == currentId } }
  var body: some View {
    VStack(spacing: 0) {
      if let attachment {
        HStack {
          AttachmentIcon(attachment: attachment, size: 24)
          Text(attachment.name).font(.system(size: 15, weight: .semibold))
            .lineLimit(1).truncationMode(.middle).cossTooltip(attachment.name)
          Text(fileSize(attachment.size)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            .fixedSize()
          Spacer()
          if store.attachmentPreviewIds.count > 1 {
            IconButton(icon: .chevronLeft, help: "上一个来源附件") { store.attachmentPreviewIndex -= 1 }.disabled(store.attachmentPreviewIndex == 0)
            Text("\(store.attachmentPreviewIndex + 1)/\(store.attachmentPreviewIds.count)").font(UIType.small)
            IconButton(icon: .chevronRight, help: "下一个来源附件") { store.attachmentPreviewIndex += 1 }.disabled(store.attachmentPreviewIndex + 1 == store.attachmentPreviewIds.count)
          }
          ActionButton(title: "打开原文件", icon: .externalLink, emphasis: .secondary) {
            store.download(attachment, preview: true)
          }
          ActionButton(title: "下载", icon: .download) { store.download(attachment) }
          IconButton(icon: .x, help: "关闭") { dismiss() }
        }.padding(20)
        CossSeparator()
        HStack(spacing: 12) {
          if !attachment.isArchive && attachment.analysis?.isEmpty == false {
            FilterBar(values: ["原文件预览", "历史分析"], selection: $tab)
          }
          Spacer(minLength: 0)
          ActionButton(title: "打开原邮件", icon: .mail) {
            dismiss()
            if attachment.messageId == store.selectedMessageId { store.mailAITab = .attachment }
            else { store.openSourceMessage(attachment.messageId, tab: .attachment) }
          }
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Palette.chrome)
        CossSeparator()
        if attachment.isArchive {
          ArchiveAttachmentView(store: store, attachmentId: attachment.id).id(attachment.id)
        } else if tab == "历史分析", let analysis = attachment.analysis, !analysis.isEmpty {
          OverlayScrollView {
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Text("历史分析").font(UIType.heading)
                Spacer()
                CopyButton(help: "复制历史分析") { analysis }
              }
              AnalysisDocumentView(text: analysis)
            }.frame(maxWidth: UILayout.document, alignment: .leading).padding(24)
              .frame(maxWidth: .infinity, alignment: .top)
          }
        } else {
          originalPreview(attachment)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white).tint(Palette.accent)
      .animation(UIMotion.disclosure(reduceMotion), value: tab)
      .onChange(of: currentId) { _, _ in tab = "原文件预览" }
      .task(id: "\(currentId)-\(tab)") {
        previewLoading = true
        previewFile?.remove(); previewFile = nil; documentPreviewURL = nil; workbookHTML = nil
        let id = currentId
        await store.loadAttachment(id)
        guard !Task.isCancelled, currentId == id, attachment?.isArchive != true, tab == "原文件预览" else { return }
        await loadOriginal()
      }
      .onDisappear {
        previewFile?.remove()
        previewFile = nil
        documentPreviewURL = nil
      }
      .storeAlert("附件操作未完成", text: { store.error }, isPresented: { store.error != nil },
        dismiss: { store.error = nil })
  }
  @ViewBuilder private func originalPreview(_ attachment: MailAttachment) -> some View {
    if let workbookHTML {
      SandboxedWebPreview(source: .html(workbookHTML)).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let previewFile {
      Group {
        if let documentPreviewURL {
          SandboxedWebPreview(source: .file(documentPreviewURL))
        } else {
          OriginalAttachmentView(url: previewFile.url, isPDF: attachment.isPDF, contentType: attachment.contentType)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).id(previewFile.url)
      HStack {
        Text(attachment.isPDF ? "PDF 原文件 · 可滚动查看全部页面"
          : OriginalAttachmentView.isMarkdown(name: attachment.name, contentType: attachment.contentType)
            ? "Markdown 原文件预览" : "系统原文件预览 · 保留文档格式、表格与图片")
          .font(.system(size: 11)).foregroundStyle(Palette.muted)
        Spacer()
        Text("特殊格式可使用上方“打开原文件”查看").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }.padding(.horizontal, 20).padding(.vertical, 10).background(Palette.chrome)
    } else if previewLoading {
      CossSpinner(label: "正在加载原文件…").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 14) {
        EmptyState(title: "暂时无法预览原文件", subtitle: previewError, icon: .file)
        ActionButton(title: "重新加载", icon: .refresh) { Task { await loadOriginal() } }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  private func loadOriginal() async {
    let id = currentId
    previewLoading = true
    previewError = ""
    defer { if currentId == id { previewLoading = false } }
    do {
      if attachment?.usesWorkbookPreview == true {
        let preview: WorkbookPreviewResponse = try await BackendService.shared.request(
          "/attachments/\(id)/preview")
        try Task.checkCancellation()
        guard id == currentId else { return }
        workbookHTML = preview.html
        return
      }
      let loaded = try await AttachmentPreviewLoader.load(
        path: "/attachments/\(id)", isPDF: attachment?.isPDF == true,
        isWord: attachment?.kind == .word)
      if Task.isCancelled || id != currentId { loaded.file.remove(); return }
      documentPreviewURL = loaded.documentURL
      previewFile = loaded.file
    } catch is CancellationError {
    } catch { if currentId == id { previewError = error.localizedDescription } }
  }
}
private struct WorkbookPreviewResponse: Decodable { let html: String }
