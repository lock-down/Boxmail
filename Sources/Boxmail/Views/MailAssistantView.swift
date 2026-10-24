import AppKit
import BoxmailCore
import SwiftUI

struct MailAIBar: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 8) {
      ForEach([MailAITab.summary, .translate, .reply]) { tab in
        Button {
          if tab != .translate && store.mailAITab == tab { store.mailAITab = nil }
          else { store.showMailAI(tab, message: message) }
        } label: {
          Label(title(tab), systemImage: tab.icon)
            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).frame(height: 30)
            .foregroundStyle(store.mailAITab == tab ? Palette.blue : Palette.muted)
            .background(store.mailAITab == tab ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(ControlFeedback(selected: store.mailAITab == tab, corner: 6))
          .controlFocus(corner: 6)
          .accessibilityAddTraits(store.mailAITab == tab ? .isSelected : [])
          .help(tab == .summary ? "总结本封邮件或查看已有总结"
            : tab == .translate ? "在原文与译文之间切换" : "为本封邮件起草回复")
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
    case .summary: return "AI 总结"
    case .translate: return store.isShowingTranslation(message) ? "显示原文" : message.translation == nil ? "翻译" : "显示译文"
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
          Text("本封邮件 · \(tab.title)").font(.system(size: 13, weight: .semibold))
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
      case .translate: EmptyView()
      case .attachment: MailAttachmentSection(store: store, message: message)
      case .reply: MailReplyView(store: store, message: message)
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
      Text("提炼正文要点、待办与关键信息。").font(.system(size: 12)).foregroundStyle(Palette.muted)
      if !working {
        ActionButton(title: "生成总结", icon: "sparkles", kind: .ai) {
          store.generate(task: "summary", message: message)
        }.disabled(store.busy.contains("agent"))
      }
    }
  }
}
