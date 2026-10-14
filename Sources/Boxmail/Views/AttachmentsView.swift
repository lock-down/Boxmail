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
        VStack(alignment: .leading, spacing: 8) {
          Text(store.destination == .analysis ? "附件解析" : "附件内容中心").font(
            .system(size: 24, weight: .bold))
          Text("集中查看文档和图片，模型理解结果可直接搜索").font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        Spacer()
        Tag(text: "\(store.accountAttachments.filter{$0.analysis != nil}.count) 个 AI 已解析", ai: true)
      }
      HStack(spacing: 10) {
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
          TextField("搜索附件名称或内容", text: $query).textFieldStyle(.plain)
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(
          RoundedRectangle(cornerRadius: 8).stroke(Palette.border)
        ).frame(maxWidth: 420)
        Spacer()
        ForEach(["全部", "PDF", "DOCX", "XLSX", "TXT", "图片"], id: \.self) { value in
          Button {
            type = value
          } label: {
            Text(value).font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 7)
              .foregroundStyle(type == value ? Palette.blue : Palette.muted).background(
                type == value ? Palette.blueSoft : .white, in: RoundedRectangle(cornerRadius: 6))
          }.buttonStyle(.plain)
        }
      }
      HStack {
        Text("\(filtered.count) 个附件").font(.system(size: 12, weight: .medium))
        Spacer()
        Text("支持 PDF、文档、表格和图片理解").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 16)], spacing: 16) {
          ForEach(filtered) { attachment in
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                Image(
                  systemName: attachment.isImage
                    ? "photo" : attachment.isPDF ? "doc.richtext" : "doc.text"
                ).font(.system(size: 27)).foregroundStyle(Palette.blue).frame(width: 48, height: 52)
                  .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                if attachment.analysis != nil { Tag(text: "AI 已解析", ai: true) }
              }
              Text(attachment.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
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
              HStack {
                Text(fileSize(attachment.size)).font(.system(size: 10)).foregroundStyle(
                  Palette.muted)
                Spacer()
                ActionButton(title: "查看与解析", icon: "sparkles", kind: .softAI) {
                  store.previewAttachment = attachment
                }
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
    }.padding(30).background(Palette.canvas)
  }
}
struct AttachmentPreviewView: View {
  @Bindable var store: MailStore
  let attachmentId: String
  @Environment(\.dismiss) private var dismiss
  @ViewState<NSImage?> private var previewImage: NSImage?
  @ViewState<String> private var previewError = ""
  var attachment: MailAttachment? { store.attachments.first { $0.id == attachmentId } }
  var body: some View {
    VStack(spacing: 0) {
      if let attachment {
        HStack {
          Image(systemName: "doc.text").foregroundStyle(Palette.blue)
          Text(attachment.name).font(.system(size: 15, weight: .semibold))
          Text(fileSize(attachment.size)).font(.system(size: 11)).foregroundStyle(Palette.muted)
          Spacer()
          ActionButton(title: "打开原文件", icon: "arrow.up.right.square") {
            store.download(attachment, preview: true)
          }
          ActionButton(title: "下载", icon: "arrow.down.to.line") { store.download(attachment) }
          IconButton(icon: "xmark", help: "关闭") { dismiss() }
        }.padding(20)
        Divider()
        HStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              HStack {
                Text(attachment.isImage ? "图片预览" : "附件内容").font(
                  .system(size: 17, weight: .semibold))
                Spacer()
                Tag(text: attachment.isImage ? "原始图片" : "本机预览")
              }
              if attachment.isImage, let image = previewImage {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 500)
              } else if attachment.isImage && previewError.isEmpty {
                ProgressView("正在加载图片…")
              } else {
                Text(
                  attachment.text.isEmpty
                    ? (attachment.isPDF
                      ? "PDF 将以页面图片交给模型理解，支持扫描文档。可打开原文件查看全部页面。"
                      : previewError.isEmpty ? "可打开原文件查看内容。" : previewError)
                    : attachment.text
                ).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).frame(
                  maxWidth: .infinity, alignment: .leading)
              }
            }.padding(24)
          }.frame(maxWidth: .infinity)
          Divider()
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              Label("AI 解析", systemImage: "sparkles").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.purple)
              Text("提炼文档或图片的摘要、关键数据与行动建议").font(.system(size: 12)).foregroundStyle(Palette.muted)
              Text(
                attachment.isPDF
                  ? "PDF 每次最多解析 20 页。页面图片会发送至已配置的 AI 服务。"
                  : attachment.isImage ? "原始图片会上传至已配置的 AI 服务。" : "文档内容会发送至已配置的 AI 服务。"
              )
              .font(.system(size: 11)).foregroundStyle(Palette.muted)
              HStack {
                ActionButton(
                  title: attachment.analysis == nil ? "开始解析" : "重新解析", icon: "sparkles", kind: .ai
                ) {
                  store.action("attachment-ai") {
                    _ = try await store.runAI(task: "attachment", attachment: attachment)
                  }
                }.disabled(!attachment.canAnalyze || store.busy.contains("agent"))
                if store.busy.contains("agent") { ProgressView().controlSize(.small) }
              }
              if let text = attachment.analysis {
                Text(text).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
              } else {
                Text("解析结果会保存到本机，可通过搜索查找其中内容。").font(.system(size: 12)).foregroundStyle(
                  Palette.muted)
              }
            }.padding(24)
          }.frame(width: 330).background(Palette.canvas)
        }
      }
    }.frame(width: 1000, height: 720).background(.white)
      .task(id: attachmentId) {
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
