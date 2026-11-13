import AppKit
import BoxmailCore
import SwiftUI

struct MailAIBar: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 8) {
      ForEach([MailAITab.summary, .translate, .reply, .conversation]) { tab in
        SelectionButton(title: title(tab), icon: tab.icon, selected: store.mailAITab == tab, size: .compact) {
          if tab != .translate && store.mailAITab == tab { store.mailAITab = nil }
          else { store.showMailAI(tab, message: message) }
        }
          .help(tab == .summary ? "结合正文与全部附件理解整封邮件，或查看已有结果"
            : tab == .translate ? "在原文与译文之间切换"
            : tab == .conversation ? "总结往来进展、未决事项，并根据上下文拟回复" : "为本封邮件起草回复")
      }
      Spacer(minLength: 0)
      if store.busy.contains("agent") && store.activeAIMessageId == message.id {
        ProgressView().controlSize(.mini)
      }
    }.padding(.horizontal, 16).frame(height: 36).background(.white)
      .animation(UIMotion.selection(reduceMotion), value: store.mailAITab)
  }
  private func title(_ tab: MailAITab) -> String {
    switch tab {
    case .summary: return "整封理解"
    case .translate: return store.isShowingTranslation(message) ? "显示原文" : message.translation == nil ? "翻译" : "显示译文"
    case .conversation: return "会话 AI"
    default: return "AI 回复"
    }
  }
}

struct MailAssistantView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let tab: MailAITab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var working: Bool { store.busy.contains("agent") && store.activeAIMessageId == message.id }
  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      if tab != .summary {
        HStack(spacing: 8) {
          Image(systemName: tab.icon).foregroundStyle(Palette.accent)
            .symbolEffect(.pulse, options: .repeating, isActive: working && !reduceMotion)
          Text(tab == .conversation ? "往来邮件 · 会话 AI" : "本封邮件 · \(tab.title)")
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          IconButton(icon: "xmark", help: "收起 AI 面板") { store.mailAITab = nil }
        }
      }
      if working && store.aiOutput(task: tab.rawValue, messageId: message.id) == nil {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("正在处理，可继续阅读其他邮件…").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.transition(.opacity)
      }
      if let error = store.mailAIErrors[message.id] {
        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
          .foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
      switch tab {
      case .summary: summary
      case .reply: MailReplyView(store: store, message: message)
      case .conversation: ConversationAIView(store: store, message: message)
      default: EmptyView()
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(tab == .summary ? Palette.blueSoft.opacity(0.55) : Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
      .animation(UIMotion.disclosure(reduceMotion), value: working)
  }
  @ViewBuilder private var summary: some View {
    if let output = store.aiOutput(task: "summary", messageId: message.id) {
      AIStreamingView(output: output)
    } else if let summary = message.summary {
      SummaryCard(store: store, message: message, summary: summary, embedded: true)
    } else {
      Text("结合正文与全部附件，梳理整体结论、待办、关键数据和跨文件差异。").font(.system(size: 12)).foregroundStyle(Palette.muted)
      if !working {
        ActionButton(title: "理解整封邮件", icon: "sparkles", color: Palette.accent) {
          store.generate(task: "summary", message: message)
        }.disabled(store.busy.contains("agent"))
      }
    }
  }
}
