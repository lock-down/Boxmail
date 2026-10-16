import AppKit
import BoxmailCore
import SwiftUI

struct AttachmentsView: View {
  @Bindable var store: MailStore
  @ViewState<String> private var query = ""
  @ViewState<String> private var type = "全部"
  var filtered: [MailAttachment] {
    store.accountAttachments.filter { a in
      (query.isEmpty
        || (a.name + " " + a.text + " " + (a.analysis ?? "")).localizedCaseInsensitiveContains(
          query))
        && (type == "全部"
          || (type == "图片" ? a.isImage : a.name.lowercased().hasSuffix(type.lowercased())))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        PageHeading(title: "附件中心", subtitle: "查找、预览和下载附件，在原邮件中使用 AI 理解")
        Spacer()
        Tag(text: "\(store.accountAttachments.filter{$0.analysis != nil}.count) 个 AI 已解析", ai: true)
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
        Text("支持 PDF、文档、表格和图片理解").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 260, maximum: 350), spacing: 16)], spacing: 16
        ) {
          ForEach(filtered) { attachment in
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                Image(
                  systemName: attachment.isImage
                    ? "photo" : attachment.isPDF ? "doc.richtext" : "doc.text"
                ).font(.system(size: 24)).foregroundStyle(Palette.blue).frame(width: 40, height: 44)
                  .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                if attachment.analysis != nil { Tag(text: "AI 已解析", ai: true) }
              }
              Text(attachment.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                .help(attachment.name)
              Text(store.messages.first { $0.id == attachment.messageId }?.subject ?? "邮件附件").font(
                .system(size: 11)
              ).foregroundStyle(Palette.muted).lineLimit(1)
              Text(
                attachment.analysis
                  ?? (attachment.text.isEmpty
                    ? (attachment.isImage
                      ? "图片可直接交给模型理解" : attachment.isPDF ? "PDF 页面可直接交给模型理解" : "可打开原文件查看")
                    : attachment.text.replacingOccurrences(of: "\n", with: " "))
              ).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(3).frame(
                height: 50, alignment: .top)
              Text(fileSize(attachment.size)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Palette.muted)
              Divider().overlay(Palette.softBorder)
              HStack(spacing: 7) {
                ActionButton(title: "预览", icon: "doc.text") {
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
            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(
              RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
          }
        }
        if filtered.isEmpty {
          EmptyState(title: "没有匹配的附件", subtitle: "同步邮箱后，邮件附件会在这里集中显示。", icon: "paperclip").frame(
            height: 300)
        }
      }
    }.workspacePage().background(Palette.canvas)
  }
  private var searchField: some View {
    HStack(spacing: 9) {
      Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
      TextField("搜索附件名称或内容", text: $query).textFieldStyle(.plain).font(.system(size: 12))
    }.padding(.horizontal, 12).frame(height: 34)
      .background(.white, in: RoundedRectangle(cornerRadius: 7))
      .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
  }
  private var typeFilters: some View {
    HStack(spacing: 4) {
      ForEach(["全部", "PDF", "DOCX", "XLSX", "TXT", "图片"], id: \.self) { value in
        FilterButton(title: value, selected: type == value, compact: true) { type = value }
      }
    }.fixedSize()
  }
}
struct AttachmentPreviewView: View {
  @Bindable var store: MailStore
  let attachmentId: String
  @Environment(\.dismiss) private var dismiss
  @ViewState<NSImage?> private var previewImage: NSImage?
  @ViewState<String> private var previewError = ""
  @ViewState<String> private var tab = "analysis"
  var attachment: MailAttachment? { store.attachments.first { $0.id == attachmentId } }
  var body: some View {
    VStack(spacing: 0) {
      if let attachment {
        HStack {
          Image(systemName: "doc.text").foregroundStyle(Palette.blue)
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
        HStack(spacing: 6) {
          FilterButton(title: "AI 理解", selected: tab == "analysis") { tab = "analysis" }
          FilterButton(title: "原文内容", selected: tab == "original") { tab = "original" }
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
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if tab == "analysis" {
              if let analysis = attachment.analysis {
                HStack {
                  Label("附件理解", systemImage: "sparkles").font(.system(size: 17, weight: .semibold))
                  Spacer()
                  IconButton(icon: "doc.on.doc", help: "复制理解结果") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(analysis, forType: .string)
                  }
                }
                AnalysisDocumentView(text: analysis)
              } else {
                EmptyState(
                  title: "还没有理解结果", subtitle: "回到原邮件后，可结合来信理解这个附件。",
                  icon: "doc.text.magnifyingglass")
              }
            } else {
              HStack {
                Text(attachment.isImage ? "图片预览" : "附件原文").font(
                  .system(size: 17, weight: .semibold))
                Spacer()
                Tag(text: attachment.isImage ? "原始图片" : "本机提取文本")
              }
              if attachment.isImage, let image = previewImage {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 580)
              } else if attachment.isImage && previewError.isEmpty {
                ProgressView("正在加载图片…")
              } else {
                Text(
                  attachment.text.isEmpty
                    ? (attachment.isPDF
                      ? "可打开原文件查看 PDF 全部页面，或回到邮件中使用 AI 理解。"
                      : previewError.isEmpty ? "可打开原文件查看完整内容。" : previewError)
                    : attachment.text.replacingOccurrences(
                      of: "\\n(?:[ \\t]*\\n){2,}", with: "\n\n", options: .regularExpression)
                )
                .font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(
                  maxWidth: .infinity, alignment: .leading)
              }
            }
          }.frame(maxWidth: 900, alignment: .leading).padding(28).frame(
            maxWidth: .infinity, alignment: .top)
        }
      }
    }.frame(width: 1080, height: 720).background(.white).tint(Palette.blue)
      .task(id: attachmentId) {
        tab = attachment?.analysis == nil ? "original" : "analysis"
        guard attachment?.isImage == true else { return }
        do {
          let file: FileResponse = try await BackendService.shared.request(
            "/attachments/\(attachmentId)")
          guard let data = Data(base64Encoded: file.content), let image = NSImage(data: data) else {
            previewError = "图片预览不可用，可打开原文件查看。"
            return
          }
          previewImage = image
        } catch { previewError = "图片预览加载失败，可打开原文件查看。" }
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
}
