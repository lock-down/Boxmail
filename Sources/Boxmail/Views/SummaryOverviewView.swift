import BoxmailCore
import SwiftUI

struct SummaryOverviewView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var showingRemoved = false
  @ViewState<Bool> private var selecting = false
  @ViewState<Set<String>> private var selected: Set<String> = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var listed: [MailMessage] { store.summaryOverviewMessages }
  private var removed: [MailMessage] { store.removedSummaryMessages }
  private var messages: [MailMessage] { showingRemoved ? removed : listed }
  private var messageIDs: Set<String> { Set(messages.map(\.id)) }
  private var outputs: [AIStreamOutput] {
    store.aiOutputs.values.filter { $0.task == "summary" && $0.accountId == store.accountId && $0.status == "running" }
      .sorted { $0.id < $1.id }
  }

  var body: some View {
    OverlayScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 24) {
          PageHeading(title: "AI 摘要总览", subtitle: "集中查看邮件要点、待办与下一步建议")
          Spacer(minLength: 12)
          ActionButton(title: store.busy.contains("summarize-unread") ? "正在总结…" : "总结未读邮件",
            icon: "sparkles", kind: .ai) {
            store.action("summarize-unread") {
              for message in store.unreadInboxMessages.filter({ $0.summary == nil }).prefix(10) {
                _ = try await store.runAI(task: "summary", message: message)
              }
            }
          }.disabled(store.busy.contains("agent") || store.unreadInboxMessages.allSatisfy { $0.summary != nil })
        }
        HStack(spacing: 24) {
          metric("列表摘要", listed.count)
          Divider().frame(height: 24)
          metric("待完成事项", listed.flatMap { $0.summary?.todos ?? [] }.filter { !$0.done }.count)
          Divider().frame(height: 24)
          metric("收件箱未读", store.unreadInboxMessages.count)
        }.padding(.vertical, 14)
          .overlay(alignment: .bottom) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
        toolbar
        if let change = store.summaryListChange, change.accountId == store.accountId {
          HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(Palette.success).accessibilityHidden(true)
            Text(change.hidden ? "已从列表移除 \(change.messageIds.count) 项，邮件内的总结已保留。"
              : "已恢复 \(change.messageIds.count) 项摘要。")
              .font(UIType.caption).foregroundStyle(Palette.muted)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            ActionButton(title: "撤销", icon: "arrow.uturn.backward", kind: .primary) { store.undoSummaryListChange() }
              .disabled(store.changingSummaryList)
            IconButton(icon: "xmark", help: "关闭摘要列表提示", size: 28) { store.summaryListChange = nil }
          }.padding(.horizontal, 14).padding(.vertical, 8)
            .background(Palette.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
        }
        if let error = store.summaryListError { WorkflowNotice(text: error, icon: "exclamationmark.circle", color: Palette.amber) }
        if !showingRemoved {
          ForEach(outputs) { output in
            VStack(alignment: .leading, spacing: 12) {
              if let message = store.messages.first(where: { $0.id == output.messageId }) {
                Text(message.subject).font(UIType.section)
              }
              AIStreamingView(output: output)
            }.padding(20).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
          }
        }
        ForEach(messages) { message in summaryRow(message) }
        if messages.isEmpty && (showingRemoved || outputs.isEmpty) {
          EmptyState(title: showingRemoved ? "没有已移除的摘要" : removed.isEmpty ? "还没有 AI 摘要" : "总结列表已清空",
            subtitle: showingRemoved ? "从列表移除的摘要会出现在这里，可随时恢复。"
              : removed.isEmpty ? "打开邮件后点击 AI 总结，或批量总结未读邮件。" : "邮件内的总结仍然保留，可在“已移除”中恢复。",
            icon: showingRemoved ? "tray" : "sparkles")
            .frame(minHeight: 240)
        }
      }.workspacePage()
    }.background(Palette.canvas)
      .animation(UIMotion.disclosure(reduceMotion), value: messages.map(\.id))
      .animation(UIMotion.disclosure(reduceMotion), value: selecting)
      .animation(UIMotion.disclosure(reduceMotion), value: store.summaryListChange?.messageIds)
      .onChange(of: messageIDs) { _, ids in
        selected.formIntersection(ids)
        if ids.isEmpty { selecting = false }
      }
      .onChange(of: showingRemoved) { _, _ in selected = []; selecting = false }
      .onChange(of: store.accountId) { _, _ in selected = []; selecting = false; showingRemoved = false }
      .onChange(of: store.restoreRevision) { _, _ in selected = []; selecting = false; showingRemoved = false }
  }

  private var toolbar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        FilterButton(title: "列表 \(listed.count)", selected: !showingRemoved) { showingRemoved = false }
        FilterButton(title: "已移除 \(removed.count)", selected: showingRemoved) { showingRemoved = true }
        Spacer(minLength: 8)
        if store.changingSummaryList { ProgressView().controlSize(.small) }
        ActionButton(title: selecting ? "取消多选" : "多选", icon: selecting ? "xmark" : "checklist", kind: .primary) {
          selecting.toggle(); selected = []
        }.disabled(messages.isEmpty || store.changingSummaryList)
        if !showingRemoved {
          ActionButton(title: "清空列表", icon: "tray", kind: .normal) {
            store.setSummaryVisibility(hidden: true, all: true)
          }.disabled(listed.isEmpty || store.changingSummaryList)
        }
      }
      if selecting {
        HStack(spacing: 12) {
          Button {
            selected = selected == messageIDs ? [] : messageIDs
          } label: {
            HStack(spacing: 7) {
              Image(systemName: selected == messageIDs ? "checkmark.square.fill" : "square")
                .frame(width: 16).foregroundStyle(Palette.accent)
              Text(selected == messageIDs ? "取消全选" : "全选")
            }.font(UIType.caption).frame(height: 30)
          }.buttonStyle(ControlFeedback(corner: 6)).controlFocus(corner: 6)
          Text("已选 \(selected.count) 项").font(UIType.caption).foregroundStyle(Palette.muted).monospacedDigit()
          Spacer()
          ActionButton(title: showingRemoved ? "恢复选中" : "移除选中", icon: showingRemoved ? "arrow.uturn.backward" : "minus.circle", kind: .primary) {
            store.setSummaryVisibility(ids: Array(selected), hidden: !showingRemoved)
          }.disabled(selected.isEmpty || store.changingSummaryList)
        }.padding(.horizontal, 12).padding(.vertical, 6)
          .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 8)).transition(.opacity)
      }
      Text(showingRemoved ? "恢复后会重新收录到列表，邮件内容不变。" : "移除或清空仅整理此列表，邮件内的 AI 总结与待办仍保留。")
        .font(UIType.small).foregroundStyle(Palette.muted)
    }
  }

  private func summaryRow(_ message: MailMessage) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        if selecting {
          Button {
            if selected.contains(message.id) { selected.remove(message.id) } else { selected.insert(message.id) }
          } label: {
            Image(systemName: selected.contains(message.id) ? "checkmark.square.fill" : "square")
              .font(.system(size: 16)).foregroundStyle(selected.contains(message.id) ? Palette.accent : Palette.muted)
              .frame(width: 28, height: 30).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback(corner: 6)).controlFocus(corner: 6)
            .accessibilityLabel("选择摘要：\(message.subject)")
            .accessibilityValue(selected.contains(message.id) ? "已选中" : "未选中")
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(message.subject).font(.system(size: 15, weight: .semibold)).lineSpacing(3)
            .lineLimit(2).help(message.subject).textSelection(.enabled)
          Text("\(message.sender) · \(displayTime(message.date))").font(UIType.small).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
        HStack(spacing: 4) {
          ActionButton(title: "打开邮件", icon: "arrow.up.right", kind: .primary) { store.openMail(message, tab: .summary) }
          IconButton(icon: showingRemoved ? "arrow.uturn.backward" : "minus.circle",
            help: showingRemoved ? "恢复摘要：\(message.subject)" : "从列表移除：\(message.subject)", size: 30) {
            store.setSummaryVisibility(ids: [message.id], hidden: !showingRemoved)
          }.disabled(store.changingSummaryList)
        }.fixedSize()
      }
      Divider().overlay(Palette.softBorder)
      if let summary = message.summary { SummaryCard(store: store, message: message, summary: summary, embedded: true) }
    }.padding(20).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
      .overlay {
        if selecting && selected.contains(message.id) {
          RoundedRectangle(cornerRadius: UILayout.radius).stroke(Palette.blue.opacity(0.55), lineWidth: 1)
            .allowsHitTesting(false)
        }
      }
  }

  private func metric(_ title: String, _ value: Int) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      Text("\(value)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
        .contentTransition(reduceMotion ? .identity : .numericText())
      Text(title).font(UIType.caption).foregroundStyle(Palette.muted)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .animation(UIMotion.selection(reduceMotion), value: value)
  }
}
