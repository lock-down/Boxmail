import AppKit
import BoxmailCore
import SwiftUI

struct MailAIBar: View {
  @Bindable var store: MailStore
  let message: MailMessage
  var body: some View {
    HStack(spacing: 4) {
      ForEach(MailAITab.allCases) { tab in
        Button {
          store.showMailAI(tab, message: message)
        } label: {
          Label(tab == .summary ? "AI 总结" : tab.title, systemImage: tab.icon)
            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 29)
            .foregroundStyle(store.mailAITab == tab ? Palette.purple : Palette.muted)
            .background(
              store.mailAITab == tab ? Palette.purpleSoft : .clear,
              in: RoundedRectangle(cornerRadius: 6)
            ).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .disabled(tab == .attachment && message.attachmentIds.isEmpty)
          .help(
            tab == .attachment && message.attachmentIds.isEmpty ? "本封邮件没有附件" : "\(tab.title)当前邮件")
      }
      Spacer(minLength: 0)
      if store.busy.contains("agent") { ProgressView().controlSize(.mini).padding(.trailing, 5) }
    }.padding(.horizontal, 14).frame(height: 42).background(.white)
  }
}

struct MailAssistantView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let tab: MailAITab
  @ViewState<String?> private var attachmentId: String?
  var mailAttachments: [MailAttachment] {
    store.attachments.filter { message.attachmentIds.contains($0.id) && $0.messageId == message.id }
  }
  var selectedAttachment: MailAttachment? {
    mailAttachments.first { $0.id == attachmentId } ?? mailAttachments.first
  }
  var working: Bool { store.busy.contains("agent") && store.activeAIMessageId == message.id }
  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(spacing: 8) {
        Image(systemName: tab.icon).foregroundStyle(Palette.purple)
        Text("本封邮件 · \(tab.title)").font(.system(size: 13, weight: .semibold))
        Spacer()
        IconButton(icon: "xmark", help: "收起 AI 面板") { store.mailAITab = nil }
      }
      if working {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("正在处理，可继续阅读其他邮件…").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
      }
      if let error = store.mailAIErrors[message.id] {
        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
          .foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
      switch tab {
      case .summary: summary
      case .translate: translation
      case .attachment: attachment
      case .reply: MailReplyView(store: store, message: message)
      }
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
  }
  @ViewBuilder private var summary: some View {
    if let summary = message.summary {
      SummaryCard(store: store, message: message, summary: summary)
    } else {
      Text("提炼正文要点、待办与关键信息。").font(.system(size: 12)).foregroundStyle(Palette.muted)
      if !working {
        ActionButton(title: "生成总结", icon: "sparkles", kind: .ai) {
          store.generate(task: "summary", message: message)
        }.disabled(store.busy.contains("agent"))
      }
    }
  }
  private var translation: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("全文翻译 · 简体中文").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.purple)
        Spacer()
        if let text = message.translation {
          IconButton(icon: "doc.on.doc", help: "复制译文") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
          }
        }
        ActionButton(title: message.translation == nil ? "翻译全文" : "重新翻译", icon: "arrow.clockwise") {
          store.generate(task: "translate", message: message)
        }.disabled(store.busy.contains("agent"))
      }
      if let text = message.translation {
        Text(text).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("译文会保存在这封邮件中，原文仍可在下方阅读。").font(.system(size: 12)).foregroundStyle(Palette.muted)
      }
    }
  }
  @ViewBuilder private var attachment: some View {
    if let file = selectedAttachment {
      if mailAttachments.count > 1 {
        Picker(
          "选择附件",
          selection: Binding(get: { selectedAttachment?.id ?? "" }, set: { attachmentId = $0 })
        ) {
          ForEach(mailAttachments) { item in Text(item.name).tag(item.id) }
        }.pickerStyle(.menu)
      }
      HStack(spacing: 9) {
        Image(systemName: file.isImage ? "photo" : "doc.text").foregroundStyle(Palette.blue)
        VStack(alignment: .leading, spacing: 4) {
          Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
          Text(fileSize(file.size)).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        Spacer()
        IconButton(icon: "arrow.up.right.square", help: "预览附件") { store.previewAttachment = file }
        IconButton(icon: "arrow.down.to.line", help: "下载附件") { store.download(file) }
      }
      HStack {
        ActionButton(title: file.analysis == nil ? "理解这个附件" : "重新理解", icon: "sparkles", kind: .ai) {
          store.generate(task: "attachment", message: message, attachment: file)
        }.disabled(!file.canAnalyze || store.busy.contains("agent"))
        Text("结合本封邮件内容分析").font(.system(size: 10)).foregroundStyle(Palette.muted)
      }
      if let analysis = file.analysis {
        Text(analysis).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
      } else {
        Text(file.canAnalyze ? "提炼摘要、关键数据和行动建议。文档或图片会发送至已配置的 AI 服务。" : "此附件暂不支持 AI 理解，可预览或下载原文件。")
          .font(.system(size: 12)).foregroundStyle(Palette.muted)
      }
      if file.isPDF {
        Text("扫描 PDF 也可直接理解，每次最多 20 页。").font(.system(size: 10)).foregroundStyle(Palette.muted)
      }
    } else {
      Text("本封邮件没有附件。").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
  }
}
