import AppKit
import BoxmailCore
import PDFKit
import SwiftUI

struct AttachmentsView: View {
  @Bindable var store: MailStore
  @ViewState<String> private var query = ""
  @ViewState<String> private var type = "全部"
  @ViewState<Set<String>> private var matchingIDs = []
  @ViewState<String> private var matchedQuery = ""
  @ViewState<String?> private var queryError: String?
  @ViewState<Bool> private var searching = false
  var searchKey: String { store.accountId + "\u{1f}" + query }
  var filtered: [MailAttachment] {
    store.accountAttachments.filter { a in
      (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || (matchedQuery == searchKey && matchingIDs.contains(a.id)))
        && matchesType(a)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        PageHeading(title: "附件中心", subtitle: "查找、预览和下载附件，在原邮件中使用 AI 理解")
        Spacer()
        Tag(text: "\(store.accountAttachments.filter(\.isAnalyzed).count) 个 AI 已解析", ai: true)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) {
          searchField.frame(minWidth: 210, idealWidth: 300, maxWidth: 360)
          Spacer(minLength: 0)
          typeFilters
        }
        VStack(alignment: .leading, spacing: 12) {
          searchField
          typeFilters
        }
      }
      HStack {
        Text("\(filtered.count) 个附件").font(.system(size: 12, weight: .medium))
        Spacer()
        Text("支持 PDF、Word、表格、PPT 和图片理解").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      if searching { ProgressView("正在搜索附件内容…").controlSize(.small) }
      if let queryError {
        HStack {
          Text(queryError).font(.system(size: 12)).foregroundStyle(Palette.amber)
          ActionButton(title: "重试", icon: "arrow.clockwise") { Task { await searchAttachments() } }
        }
      }
      OverlayScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16
        ) {
          ForEach(filtered) { attachment in
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                AttachmentIcon(attachment: attachment, size: 27)
                Spacer()
                if attachment.isAnalyzed { Tag(text: "AI 已解析", ai: true) }
              }
              Text(attachment.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                .frame(minHeight: 36, alignment: .topLeading)
                .help(attachment.name)
              Text(store.messages.first { $0.id == attachment.messageId }?.subject ?? "邮件附件").font(
                .system(size: 11)
              ).foregroundStyle(Palette.muted).lineLimit(1)
              Text(AITextStyle.preview(
                attachment.analysis ?? attachment.analysisPreview ?? attachment.textPreview
                  ?? (attachment.text.isEmpty
                    ? (attachment.isImage
                      ? "图片可直接交给模型理解" : attachment.isPDF ? "PDF 页面可直接交给模型理解"
                        : attachment.isPresentation ? "PPT 可逐页理解文字、图表和图片" : "可打开原文件查看")
                    : attachment.text.replacingOccurrences(of: "\n", with: " "))
              )).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(3).lineSpacing(4).frame(
                height: 56, alignment: .top)
              Text(fileSize(attachment.size)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Palette.muted)
              Divider().overlay(Palette.softBorder)
              HStack(spacing: 7) {
                ActionButton(title: "预览", icon: "doc.text", kind: .softAI) {
                  store.previewAttachment = attachment
                }
                if let mail = store.messages.first(where: { $0.id == attachment.messageId }) {
                  ActionButton(title: "原邮件", icon: "envelope") {
                    store.openMail(mail, tab: .attachment)
                  }
                }
                Spacer(minLength: 0)
                IconButton(icon: "arrow.down.to.line", help: "下载附件") { store.download(attachment) }
              }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
              .background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
          }
        }
        if filtered.isEmpty && !searching && queryError == nil {
          EmptyState(title: "没有匹配的附件", subtitle: "同步邮箱后，邮件附件会在这里集中显示。", icon: "paperclip").frame(
            height: 300)
        }
      }
    }.workspacePage().background(Palette.canvas)
      .task(id: searchKey) { await searchAttachments() }
  }
  private func searchAttachments() async {
    let key = searchKey
    queryError = nil
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      matchingIDs = []
      matchedQuery = key
      searching = false
      return
    }
    searching = true
    defer { if key == searchKey { searching = false } }
    do {
      try await Task.sleep(for: .milliseconds(180))
      var parameters = URLComponents()
      parameters.queryItems = [
        URLQueryItem(name: "accountId", value: store.accountId),
        URLQueryItem(name: "q", value: query),
      ]
      let result: AttachmentSearchResponse = try await BackendService.shared.request(
        "/attachments/search?\(parameters.percentEncodedQuery ?? "")")
      try Task.checkCancellation()
      guard key == searchKey else { return }
      matchingIDs = Set(result.ids)
      matchedQuery = key
    } catch is CancellationError {
    } catch { if key == searchKey { queryError = error.localizedDescription } }
  }
  private var searchField: some View {
    SearchField(placeholder: "搜索附件名称或内容", text: $query)
  }
  private var typeFilters: some View {
    FilterBar(values: ["全部", "PDF", "Word", "表格", "PPT", "TXT", "图片"], selection: $type, compact: true)
  }
  private func matchesType(_ attachment: MailAttachment) -> Bool {
    switch type {
    case "PDF": return attachment.isPDF
    case "Word": return attachment.kind == .word
    case "表格": return attachment.isSpreadsheet
    case "PPT": return attachment.isPresentation
    case "TXT": return attachment.kind == .text
    case "图片": return attachment.isImage
    default: return true
    }
  }
}
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
                      icon: "sparkles", kind: .ai
                    ) { store.generate(task: "attachment", message: mail, attachment: attachment) }
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
                if let analysis = attachment.analysis {
                  HStack {
                    Label("附件理解", systemImage: "sparkles").font(
                      .system(size: 17, weight: .semibold))
                    Spacer()
                    CopyButton(help: "复制理解结果") {
                      NSPasteboard.general.clearContents()
                      NSPasteboard.general.setString(analysis, forType: .string)
                    }
                  }
                  AnalysisDocumentView(text: analysis).transition(UIMotion.reveal(reduceMotion))
                } else {
                  EmptyState(
                    title: "还没有理解结果", subtitle: "可理解这个附件，或在原邮件中一键批量理解全部附件。",
                    icon: "doc.text.magnifyingglass")
                }
              }
            }.frame(maxWidth: UILayout.document, alignment: .leading).padding(28).frame(
              maxWidth: .infinity, alignment: .top)
          }
        }
      }
    }.frame(width: 1080, height: 720).background(.white).tint(Palette.blue)
      .animation(UIMotion.disclosure(reduceMotion), value: tab)
      .task(id: attachmentId) {
        tab = "原文件预览"
        await store.loadAttachment(attachmentId)
      }
      .task(id: "\(attachmentId)-\(tab)") {
        guard tab == "原文件预览", previewFile == nil, workbookHTML == nil else { return }
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
      WorkbookAttachmentView(html: workbookHTML).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let previewFile {
      Group {
        if let documentPreviewURL {
          DocumentAttachmentView(url: documentPreviewURL)
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
      let file: FileResponse = try await BackendService.shared.request(
        "/attachments/\(attachmentId)")
      try Task.checkCancellation()
      guard let data = Data(base64Encoded: file.content) else {
        throw BackendService.shared.failure("原文件数据无效，请重新下载附件。")
      }
      let saved = try AttachmentPreviewFile(name: file.name, data: data)
      var keep = false
      defer { if !keep { saved.remove() } }
      if attachment?.isPDF == true {
        guard let pdf = PDFDocument(url: saved.url), !pdf.isLocked else {
          throw BackendService.shared.failure("PDF 已加密或文件损坏，请使用“打开原文件”在原应用中查看。")
        }
      }
      if attachment?.kind == .word {
        let url = try await SystemDocumentPreview.prepare(saved)
        try Task.checkCancellation()
        documentPreviewURL = url
      }
      try Task.checkCancellation()
      previewFile = saved
      keep = true
    } catch is CancellationError {
    } catch { previewError = error.localizedDescription }
  }
}
private struct WorkbookPreviewResponse: Decodable { let html: String }
private struct AttachmentSearchResponse: Decodable { let ids: [String] }
