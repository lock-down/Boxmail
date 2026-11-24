import BoxmailCore
import SwiftUI

struct FollowUpsView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: FollowUpStore
  @ViewState private var editing: FollowUp?
  private var visible: [FollowUp] {
    workspace.items.filter { item in
      switch workspace.filter {
      case "等待对方": return item.state == "waiting" && !item.isSnoozed
      case "已延后": return item.state != "completed" && item.isSnoozed
      case "已完成": return item.state == "completed"
      case "已到期": return item.isDue
      default: return item.state == "mine" && !item.isSnoozed
      }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        FilterBar(values: ["待我处理", "等待对方", "已到期", "已延后", "已完成"], selection: $workspace.filter, compact: true)
        Text("\(visible.count) 项").font(UIType.caption).foregroundStyle(Palette.muted).monospacedDigit()
        Spacer(minLength: 0)
        ActionButton(title: "提醒设置", icon: .notification3Line, size: .compact) {
          store.settingsTab = "常用"
          store.showSettings = true
        }
      }
      if let error = workspace.error {
        Text(error).foregroundStyle(Palette.amber).font(UIType.caption)
      }
      if visible.isEmpty {
        EmptyState(
          title: "暂无\(workspace.filter == "待我处理" ? "待处理事项" : workspace.filter + "事项")",
          subtitle: "在邮件、摘要待办或会话建议中选择“收录跟进”，行动和来源会一起保留", icon: .listCheck3)
      } else {
        WorkspaceList(
          items: visible, scrollPosition: workspace.scrollPosition, bordered: false,
          header: { EmptyView() }, footer: { EmptyView() }
        ) { item in
          HStack(alignment: .top, spacing: 16) {
            IconButton(
              icon: item.state == "completed" ? .checkboxCircleFill : .checkboxBlankCircleLine,
              help: item.state == "completed" ? "重新打开" : "完成跟进",
              color: item.state == "completed" ? Palette.success : Palette.muted
            ) {
              Task {
                await workspace.save(
                  ["state": item.state == "completed" ? "mine" : "completed"], id: item.id)
              }
            }
            VStack(alignment: .leading, spacing: 8) {
              Text(item.title).font(.system(size: 14, weight: .medium)).strikethrough(
                item.state == "completed"
              )
              .fixedSize(horizontal: false, vertical: true)
              MailSourceButton(sender: item.subject, date: "", subject: item.subject) {
                store.openSourceMessage(item.replyMessageId ?? item.messageId)
              }
              if let date = item.effectiveDate {
                Text(
                  "\(item.isSnoozed ? "延后至" : "跟进时间") \(date.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(UIType.small).foregroundStyle(item.isDue ? Palette.amber : Palette.muted)
              } else if !item.dueText.isEmpty {
                Text("原文期限：\(item.dueText)，请确认具体时间").font(UIType.small).foregroundStyle(
                  Palette.muted)
              }
              if item.replyMessageId != nil {
                Text("会话已有对方回信，等待提醒已解除").font(UIType.small).foregroundStyle(Palette.success)
              } else if item.reminderCancelled {
                Text("本次提醒已取消").font(UIType.small).foregroundStyle(Palette.muted)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: .equalizer3Line, help: "编辑跟进") { editing = item }
          }.padding(16).accessibilityElement(children: .contain)
            .background(item.id == workspace.selectedId ? Palette.selected : Palette.paper)
            .contextMenu {
              Button("取消本次等待提醒") {
                Task { await workspace.save(["cancelReminder": true], id: item.id) }
              }
              Button("取消延后") {
                Task { await workspace.save(["snoozedUntil": NSNull()], id: item.id) }
              }
              Button("移除跟进项") { Task { await workspace.remove(item) } }
            }
        }
      }
    }
      .task {
        await workspace.load()
        if let id = workspace.editorRequest {
          editing = workspace.items.first { $0.id == id }
          workspace.editorRequest = nil
        }
      }
      .onChange(of: workspace.editorRequest) { _, id in
        if let id {
          editing = workspace.items.first { $0.id == id }
          workspace.editorRequest = nil
        }
      }
      .sheet(item: $editing) { item in
        FollowUpEditor(workspace: workspace, item: item, startSnoozed: workspace.suggestSnooze)
          .workspaceSheet(.categories)
      }
  }
}
