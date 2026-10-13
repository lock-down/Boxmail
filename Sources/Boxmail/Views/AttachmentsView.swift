import BoxmailCore
import SwiftUI

struct AttachmentsView: View {
  @Bindable var store: MailStore
  @ViewState<String> private var query = ""
  @ViewState<String> private var type = "全部"
  var filtered: [MailAttachment] {
    store.accountAttachments.filter { a in
      (query.isEmpty || (a.name + " " + a.text).localizedCaseInsensitiveContains(query))
        && (type == "全部" || a.name.lowercased().hasSuffix(type.lowercased()))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        VStack(alignment: .leading, spacing: 8) {
          Text(store.destination == .analysis ? "附件解析" : "附件内容中心").font(
            .system(size: 24, weight: .bold))
          Text("集中查看邮件附件，直接搜索文件里的内容").font(.system(size: 12)).foregroundStyle(Palette.muted)
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
        ForEach(["全部", "PDF", "DOCX", "XLSX", "TXT"], id: \.self) { value in
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
        Text("支持文本 PDF、DOCX、XLSX、TXT、CSV").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 16)], spacing: 16) {
          ForEach(filtered) { attachment in
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                Image(
                  systemName: attachment.name.lowercased().hasSuffix("pdf")
                    ? "doc.richtext" : "doc.text"
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
                attachment.text.isEmpty
                  ? "暂无可提取文本" : attachment.text.replacingOccurrences(of: "\n", with: " ")
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
                Text("附件文本").font(.system(size: 17, weight: .semibold))
                Spacer()
                Tag(text: "本机提取")
              }
              Text(
                attachment.text.isEmpty
                  ? "该文件没有可提取的文本。扫描 PDF、图片及旧版 Office 文件暂不支持 OCR。可以打开原文件查看。" : attachment.text
              ).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).frame(
                maxWidth: .infinity, alignment: .leading)
            }.padding(24)
          }.frame(maxWidth: .infinity)
          Divider()
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              Label("AI 解析", systemImage: "sparkles").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.purple)
              Text("提炼文件摘要、关键数据与行动建议").font(.system(size: 12)).foregroundStyle(Palette.muted)
              HStack {
                ActionButton(
                  title: attachment.analysis == nil ? "开始解析" : "重新解析", icon: "sparkles", kind: .ai
                ) {
                  store.action("attachment-ai") {
                    _ = try await store.runAI(task: "attachment", attachment: attachment)
                  }
                }.disabled(attachment.text.isEmpty || store.busy.contains("agent"))
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
