import AppKit
import BoxmailCore
import SwiftUI

struct MailAIBar: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @Namespace private var selection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 4) {
      ForEach(MailAITab.allCases) { tab in
        Button {
          withAnimation(UIMotion.disclosure(reduceMotion)) { store.showMailAI(tab, message: message) }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: tab.icon)
              .symbolEffect(.pulse, options: .repeating,
                isActive: !reduceMotion && store.busy.contains("agent")
                  && store.activeAIMessageId == message.id && store.mailAITab == tab)
            Text(tab == .summary ? "AI 总结" : tab.title)
          }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 30)
            .foregroundStyle(store.mailAITab == tab ? Palette.accent : Palette.muted)
            .background {
              if store.mailAITab == tab {
                if reduceMotion {
                  RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft)
                } else {
                  RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft)
                    .matchedGeometryEffect(id: "ai-tab", in: selection)
                }
              }
            }.contentShape(Rectangle())
        }.buttonStyle(ControlFeedback(selected: store.mailAITab == tab, corner: 6))
          .controlFocus(corner: 6)
          .accessibilityAddTraits(store.mailAITab == tab ? .isSelected : [])
          .disabled(tab == .attachment && message.attachmentIds.isEmpty)
          .help(
            tab == .attachment && message.attachmentIds.isEmpty ? "本封邮件没有附件" : "\(tab.title)当前邮件")
      }
      Spacer(minLength: 0)
      if store.busy.contains("agent") { ProgressView().controlSize(.mini).padding(.trailing, 5) }
    }.padding(.horizontal, 16).frame(height: 44).background(.white)
      .animation(UIMotion.selection(reduceMotion), value: store.mailAITab)
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
      if working {
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
      case .translate: translation
      case .attachment: MailAttachmentSection(store: store, message: message)
      case .reply: MailReplyView(store: store, message: message)
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(tab == .summary ? Palette.blueSoft.opacity(0.55) : Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
      .animation(UIMotion.disclosure(reduceMotion), value: working)
  }
  @ViewBuilder private var summary: some View {
    if let summary = message.summary {
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
  private var translation: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("全文翻译 · 简体中文").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
        Spacer()
        if let text = message.translation {
          CopyButton(help: "复制译文") {
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
}
