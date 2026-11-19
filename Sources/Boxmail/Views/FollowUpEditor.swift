import BoxmailCore
import SwiftUI

struct FollowUpEditor: View {
  @Bindable var workspace: FollowUpStore
  let item: FollowUp
  let startSnoozed: Bool
  @Environment(\.dismiss) private var dismiss
  @ViewState private var title = ""
  @ViewState private var state = "mine"
  @ViewState private var hasDue = false
  @ViewState private var due = Date()
  @ViewState private var snoozed = false
  @ViewState private var until = Date()
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text("编辑跟进").font(UIType.heading)
        Text(item.subject).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(2)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Palette.paper)
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 20) {
          WorkflowField(title: "行动") {
            WorkflowTextInput(label: "行动标题", placeholder: "需要完成的下一步", text: $title)
          }
          WorkflowField(title: "状态") {
            WorkflowSelection(
              title: "跟进状态", selection: $state,
              options: [("mine", "待我处理"), ("waiting", "等待对方"), ("completed", "已完成")]
            )
            .frame(width: 240)
          }
          Divider().overlay(Palette.softBorder)
          VStack(spacing: 12) {
            timing("跟进提醒", icon: "bell", enabled: $hasDue, date: $due, fieldTitle: "跟进时间")
            timing("稍后处理", icon: "clock", enabled: $snoozed, date: $until, fieldTitle: "重新出现时间")
          }
          WorkflowNotice(
            text: "\(TimeZone.current.identifier) · 到期提醒在 Boxmail 运行时处理；退出或睡眠后会在恢复运行时继续。取消提醒不会完成跟进。"
          )
          if let error = workspace.error { WorkflowNotice(text: error, color: Palette.amber) }
        }.font(UIType.body).padding(24)
      }
      SettingsActionBar(
        primaryTitle: "保存", primaryDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
        cancel: { dismiss() }, primary: save
      ) { EmptyView() }
    }.background(Palette.paper).onAppear {
      title = item.title
      state = item.state
      hasDue = item.dueAt != nil
      due = item.dueAt.flatMap(MailTimestamp.date) ?? FollowUpHour.next(after: .now)
      snoozed = item.isSnoozed || startSnoozed
      until = item.snoozedUntil.flatMap(MailTimestamp.date) ?? FollowUpHour.next(after: .now)
      workspace.suggestSnooze = false
    }
  }
  private func timing(_ title: String, icon: String, enabled: Binding<Bool>, date: Binding<Date>, fieldTitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: enabled) {
        HStack(spacing: 8) {
          Image(systemName: icon).frame(width: 16).foregroundStyle(Palette.muted).accessibilityHidden(true)
          Text(title)
          Spacer(minLength: 0)
        }
      }.toggleStyle(.switch).controlSize(.small).tint(Palette.blue)
        .frame(height: 32)
      if enabled.wrappedValue { FollowUpDateTimeField(title: fieldTitle, date: date) }
    }
  }
  private func save() {
    Task {
      if await workspace.save(
        [
          "title": title, "state": state,
          "dueAt": hasDue ? ISO8601DateFormatter().string(from: due) as Any : NSNull(),
          "snoozedUntil": snoozed ? ISO8601DateFormatter().string(from: until) as Any : NSNull(),
        ], id: item.id) != nil
      {
        dismiss()
      }
    }
  }
}
