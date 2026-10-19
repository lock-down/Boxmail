import AppKit
import BoxmailCore
import SwiftUI

struct SummaryCard: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let summary: MailSummary
  var embedded = false
  @ViewState<Bool> private var collapsed = false
  @ViewState<Bool> private var showKeyInfo = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 7) {
        Label("AI 已为您总结", systemImage: "sparkles")
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
        if message.accountId == "demo" {
          Text("演示示例").font(UIType.small).foregroundStyle(Palette.muted)
        }
        Spacer(minLength: 0)
        IconButton(icon: "arrow.clockwise", help: "重新生成总结") {
          store.generate(task: "summary", message: message)
        }.disabled(store.busy.contains("agent"))
        CopyButton(help: "复制总结") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(summary.plainText, forType: .string)
        }
        if embedded && store.destination != .summary {
          IconButton(icon: "xmark", help: "收起 AI 面板") { store.mailAITab = nil }
        } else {
          IconButton(icon: collapsed ? "chevron.down" : "chevron.up",
            help: collapsed ? "展开总结" : "折叠总结") { collapsed.toggle() }
        }
      }
      if store.destination == .summary, let error = store.mailAIErrors[message.id] {
        Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
      }
      if !collapsed {
        SummaryContentLayout {
          overview.layoutValue(key: SummarySectionKey.self, value: .overview)
          followUp.layoutValue(key: SummarySectionKey.self, value: .followUp)
          if !summary.keyInfo.isEmpty {
            keyInformation.layoutValue(key: SummarySectionKey.self, value: .keyInfo)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
          .transition(UIMotion.reveal(reduceMotion))
      }
    }.foregroundStyle(Palette.ink).padding(embedded ? 0 : 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(embedded ? Color.clear : Palette.blueSoft.opacity(0.55),
        in: RoundedRectangle(cornerRadius: UILayout.radius))
      .animation(UIMotion.disclosure(reduceMotion), value: collapsed)
      .environment(\.openURL, OpenURLAction { url in
        guard MailHTMLDocument.externalLink(url) else { return .discarded }
        NSWorkspace.shared.open(url)
        return .handled
      })
  }
  private var overview: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("内容概要").font(.system(size: 12, weight: .semibold))
      Text(AITextStyle.inline(summary.overviewText)).font(AITextStyle.body).lineSpacing(6)
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private var keyInformation: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button { showKeyInfo.toggle() } label: {
        HStack(spacing: 6) {
          Text("关键信息").font(.system(size: 12, weight: .semibold))
          Text("\(summary.keyInfo.count)").font(UIType.small).foregroundStyle(Palette.muted)
          Spacer(minLength: 4)
          Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
            .rotationEffect(.degrees(showKeyInfo ? 0 : -90)).foregroundStyle(Palette.muted)
            .accessibilityHidden(true)
        }.foregroundStyle(Palette.ink).padding(.vertical, 3).contentShape(Rectangle())
      }.buttonStyle(ControlFeedback()).controlFocus()
        .accessibilityLabel("关键信息，\(summary.keyInfo.count) 项")
        .accessibilityValue(showKeyInfo ? "已展开" : "已收起")
      if showKeyInfo {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(Array(summary.keyInfo.enumerated()), id: \.offset) { _, info in
            VStack(alignment: .leading, spacing: 5) {
              Text(info.label).font(UIType.small).foregroundStyle(Palette.muted)
              Text(AITextStyle.inline(info.value)).font(UIType.caption).lineSpacing(4)
            }.fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }.textSelection(.enabled).transition(UIMotion.reveal(reduceMotion))
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: showKeyInfo)
  }
  private var followUp: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Text("待处理").font(.system(size: 12, weight: .semibold))
        ForEach(summary.todos) { todo in
          Button { store.toggleTodo(message: message, todo: todo) } label: {
            HStack(alignment: .top, spacing: 9) {
              Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15)).foregroundStyle(todo.done ? Palette.success : Palette.muted)
                .symbolEffect(.bounce, value: todo.done && !reduceMotion).padding(.top, 1)
                .symbolEffectsRemoved(reduceMotion)
              VStack(alignment: .leading, spacing: 4) {
                Text(AITextStyle.inline(todo.title)).strikethrough(todo.done)
                  .foregroundStyle(todo.done ? Palette.muted : Palette.ink)
                  .fixedSize(horizontal: false, vertical: true)
                if !todo.due.isEmpty {
                  Label(todo.due, systemImage: "calendar").font(UIType.small)
                    .foregroundStyle(Palette.amber).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
              }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }.font(AITextStyle.body).lineSpacing(4).padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback()).controlFocus()
            .disabled(store.busy.contains("todo"))
            .accessibilityLabel(todo.title).accessibilityValue(todo.done ? "已完成" : "待处理")
            .animation(UIMotion.selection(reduceMotion), value: todo.done)
        }
        if summary.todos.isEmpty {
          Text("暂无明确待办。").font(UIType.caption).foregroundStyle(Palette.muted)
        }
      }
      if let steps = summary.nextSteps, !steps.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("您可继续").font(.system(size: 12, weight: .semibold)).padding(.bottom, 3)
          ForEach(steps) { step in
            if ["reply", "attachments"].contains(step.action) {
              Button { store.followSummary(step, in: message) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Image(systemName: step.action == "reply" ? "arrowshape.turn.up.left" : "paperclip")
                    .frame(width: 15).accessibilityHidden(true)
                  Text(step.title).fixedSize(horizontal: false, vertical: true)
                  Spacer(minLength: 0)
                  Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                }.font(UIType.caption).foregroundStyle(Palette.accent).multilineTextAlignment(.leading)
                  .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
              }.buttonStyle(ControlFeedback()).controlFocus().help(step.title)
                .disabled(store.busy.contains("agent"))
            } else {
              Text(step.title).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                .padding(.vertical, 4).textSelection(.enabled)
            }
          }
        }
      }
    }
  }
}
