import AppKit
import BoxmailCore
import SwiftUI

struct SummaryCard: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let summary: MailSummary
  var embedded = false
  var allowsCollapse = true
  var showOriginal: (() -> Void)?
  @ViewState<Bool> private var collapsed = false
  @ViewState<Bool> private var overviewExpanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(
    store: MailStore, message: MailMessage, summary: MailSummary, embedded: Bool = false,
    allowsCollapse: Bool = true,
    showOriginal: (() -> Void)? = nil
  ) {
    self.store = store
    self.message = message
    self.summary = summary
    self.embedded = embedded
    self.allowsCollapse = allowsCollapse
    self.showOriginal = showOriginal
  }
  private var inWorkspace: Bool { embedded && store.destination == .summary }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 7) { heading; Spacer(minLength: 0); actions }
        VStack(alignment: .leading, spacing: 8) {
          heading
          HStack { Spacer(minLength: 0); actions }
        }
      }
      if store.destination == .summary, let error = store.mailAIErrors[message.id] {
        Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
      }
      if !collapsed {
        MailAIContextNotice(context: summary.context, attachmentCount: message.attachmentIds.count)
        SummaryContentLayout {
          VStack(alignment: .leading, spacing: 16) {
            overview
            SummaryFactsView(facts: summary.keyInfo)
          }.frame(maxWidth: .infinity, alignment: .topLeading)
          if !summary.todos.isEmpty || summary.nextSteps?.isEmpty == false { followUp }
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
  private var heading: some View {
    HStack(spacing: 7) {
      Label("整封理解", systemImage: "doc.text.magnifyingglass")
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
      if !inWorkspace, message.accountId == "demo" {
        Text("演示示例").font(UIType.small).foregroundStyle(Palette.muted)
      }
    }.fixedSize()
  }
  private var actions: some View {
    HStack(spacing: 7) {
      if !inWorkspace {
        ActionButton(title: "查看原文", icon: "arrow.down", size: .compact) {
          if let showOriginal { showOriginal() }
          else { store.openMail(message) }
        }
      }
      ActionButton(title: "重新生成", icon: "arrow.clockwise", size: .compact) {
        store.generate(task: "summary", message: message)
      }.disabled(store.busy.contains("agent"))
      CopyButton(help: "复制总结") { summary.plainText }
      if embedded && store.destination != .summary {
        IconButton(icon: "xmark", help: "收起 AI 面板") { store.mailAITab = nil }
      } else if allowsCollapse {
        IconButton(icon: collapsed ? "chevron.down" : "chevron.up",
          help: collapsed ? "展开总结" : "折叠总结") { collapsed.toggle() }
      }
    }.fixedSize()
  }
  private var overview: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 4) {
        sectionTitle("内容概要")
        Spacer(minLength: 4)
        if !inWorkspace {
          ActionButton(title: overviewExpanded ? "收起概要" : "展开概要", size: .compact) {
            overviewExpanded.toggle()
          }
        }
      }.frame(minHeight: UIControlSize.compact.height)
      if inWorkspace || overviewExpanded {
        AnalysisDocumentView(text: summary.overviewText)
      } else {
        Text(AITextStyle.preview(summary.overviewText)).font(AITextStyle.body).lineSpacing(6)
          .lineLimit(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
  private var followUp: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !summary.todos.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          sectionTitle("待处理").frame(minHeight: UIControlSize.compact.height)
          ForEach(summary.todos) { todo in
            SummaryTodoRow(todo: todo, compact: false, canToggle: !store.busy.contains("todo")) {
              store.toggleTodo(message: message, todo: todo)
            } collect: {
              store.collectFollowUp(message: message, todo: todo)
            }
          }
        }
      }
      if let steps = summary.nextSteps, !steps.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          sectionTitle("下一步")
          ForEach(steps) { step in
            if ["reply", "attachments"].contains(step.action) {
              Button { store.followSummary(step, in: message) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Image(systemName: step.action == "reply" ? "arrowshape.turn.up.left" : "paperclip")
                    .frame(width: 15).accessibilityHidden(true)
                  Text(AITextStyle.inline(step.title)).fixedSize(horizontal: false, vertical: true)
                  Spacer(minLength: 0)
                  Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                }.font(UIType.caption).foregroundStyle(Palette.accent).multilineTextAlignment(.leading)
                  .controlLabel(size: .compact, verticalInset: 6, fillsWidth: true, alignment: .leading)
              }.buttonStyle(ControlFeedback()).controlFocus().help(step.title)
                .disabled(store.busy.contains("agent"))
            } else {
              Text(AITextStyle.inline(step.title)).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                .padding(.vertical, 4).textSelection(.enabled)
            }
          }
        }
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title).font(UIType.section).accessibilityAddTraits(.isHeader)
  }
}
