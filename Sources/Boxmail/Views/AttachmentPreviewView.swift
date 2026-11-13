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
  @ViewState<Bool> private var previewLoading = false
  @ViewState<String> private var previewError = ""
  @ViewState<String> private var tab = "原文件预览"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var attachment: MailAttachment? { store.attachments.first { $0.id == attachmentId } }
  var body: some View {
    VStack(spacing: 0) {
      if let attachment {
        HStack {
          AttachmentIcon(attachment: attachment, size: 20)
          Text(attachment.name).font(.system(size: 15, weight: .semibold))
            .lineLimit(1).truncationMode(.middle).help(attachment.name)
          Text(fileSize(attachment.size)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            .fixedSize()
          Spacer()
          ActionButton(title: "打开原文件", icon: "arrow.up.right.square") {
            store.download(attachment, preview: true)
          }
          ActionButton(title: "下载", icon: "arrow.down.to.line") { store.download(attachment) }
          IconButton(icon: "xmark", help: "关闭") { dismiss() }
        }.padding(20)
        Divider()
        if attachment.isArchive {
          ArchiveAttachmentView(store: store, attachmentId: attachment.id)
        } else {
          HStack(spacing: 12) {
            FilterBar(values: ["原文件预览", "AI 理解"], selection: $tab)
            Spacer()
            if let mail = store.messages.first(where: { $0.id == attachment.messageId }) {
              Text("来自：\(mail.subject)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.middle).help(mail.subject)
              ActionButton(title: "打开原邮件", icon: "envelope") {
                dismiss()
                store.openMail(mail, tab: .attachment)
              }
            }
          }.padding(.horizontal, 20).padding(.vertical, 12).background(Palette.chrome)
          Divider()
          if tab == "原文件预览" {
            originalPreview(attachment)
          } else {
            OverlayScrollView {
              VStack(alignment: .leading, spacing: 20) {
                if tab == "AI 理解" {
                  if let mail = store.messages.first(where: { $0.id == attachment.messageId }) {
                    HStack {
                      ActionButton(
                        title: attachment.isAnalyzed ? "重新理解这个附件" : "理解这个附件",
                        icon: "sparkles", color: Palette.accent
                      ) {
                        store.generate(task: "attachment", message: mail, attachment: attachment)
                      }
                      .disabled(
                        !attachment.canAnalyze || store.busy.contains("agent")
                          || store.attachmentBatch(for: mail)?.status == "running")
                      if store.attachmentBatch(for: mail)?.status == "running" {
                        Text("正在批量理解本封邮件附件…").font(.system(size: 11)).foregroundStyle(Palette.muted)
                      }
                      Spacer()
                    }
                    if let error = store.mailAIErrors[mail.id] {
                      Text(error).font(.system(size: 12)).foregroundStyle(Palette.amber)
                    }
                  }
                  if let output = store.aiOutput(
                    task: "attachment", messageId: attachment.messageId, attachmentId: attachment.id
                  ) {
                    AIStreamingView(output: output)
                  } else if let analysis = attachment.analysis {
                    HStack {
                      Label("附件理解", systemImage: "sparkles").font(
                        .system(size: 17, weight: .semibold))
                      Spacer()
                      CopyButton(help: "复制理解结果") { analysis }
                    }
                    AnalysisDocumentView(text: analysis).transition(UIMotion.reveal(reduceMotion))
                  } else {
                    EmptyState(
                      title: "还没有独立理解结果", subtitle: "可深入理解这个附件，或在原邮件中结合正文与全部附件进行整封理解。",
                      icon: "doc.text.magnifyingglass")
                  }
                }
              }.frame(maxWidth: UILayout.document, alignment: .leading).padding(28).frame(
                maxWidth: .infinity, alignment: .top)
            }
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white).tint(Palette.blue)
      .animation(UIMotion.disclosure(reduceMotion), value: tab)
      .task(id: attachmentId) {
        tab = "原文件预览"
        await store.loadAttachment(attachmentId)
      }
      .task(id: "\(attachmentId)-\(tab)") {
        guard attachment?.isArchive != true, tab == "原文件预览", previewFile == nil, workbookHTML == nil
        else { return }
        await loadOriginal()
      }
      .onDisappear {
        previewFile?.remove()
        previewFile = nil
        documentPreviewURL = nil
      }
      .alert(
        "解析未完成",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("确定") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
  }
  @ViewBuilder private func originalPreview(_ attachment: MailAttachment) -> some View {
    if let workbookHTML {
      SandboxedWebPreview(source: .html(workbookHTML)).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let previewFile {
      Group {
        if let documentPreviewURL {
          SandboxedWebPreview(source: .file(documentPreviewURL))
        } else {
          OriginalAttachmentView(url: previewFile.url, isPDF: attachment.isPDF)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).id(previewFile.url)
      HStack {
        Text(attachment.isPDF ? "PDF 原文件 · 可滚动查看全部页面" : "系统原文件预览 · 保留文档格式、表格与图片")
          .font(.system(size: 11)).foregroundStyle(Palette.muted)
        Spacer()
        Text("特殊格式可使用上方“打开原文件”查看").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }.padding(.horizontal, 20).padding(.vertical, 10).background(Palette.chrome)
    } else if previewLoading {
      ProgressView("正在加载原文件…").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 14) {
        EmptyState(title: "暂时无法预览原文件", subtitle: previewError, icon: "doc")
        ActionButton(title: "重新加载", icon: "arrow.clockwise") { Task { await loadOriginal() } }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  private func loadOriginal() async {
    previewLoading = true
    previewError = ""
    defer { previewLoading = false }
    do {
      if attachment?.usesWorkbookPreview == true {
        let preview: WorkbookPreviewResponse = try await BackendService.shared.request(
          "/attachments/\(attachmentId)/preview")
        try Task.checkCancellation()
        workbookHTML = preview.html
        return
      }
      let loaded = try await AttachmentPreviewLoader.load(
        path: "/attachments/\(attachmentId)", isPDF: attachment?.isPDF == true,
        isWord: attachment?.kind == .word)
      try Task.checkCancellation()
      documentPreviewURL = loaded.documentURL
      previewFile = loaded.file
    } catch is CancellationError {
    } catch { previewError = error.localizedDescription }
  }
}
private struct WorkbookPreviewResponse: Decodable { let html: String }
