import BoxmailCore
import SwiftUI

struct FollowUpEditor: View {
  private static let snoozeMinutes = 15
  private static let fieldWidth: CGFloat = 240

  @Bindable var workspace: FollowUpStore
  let row: ChecklistRow
  let item: ChecklistItem
  let startSnoozed: Bool
  @Environment(\.dismiss) private var dismiss
  @ViewState private var title = ""
  @ViewState private var state = "mine"
  @ViewState private var hasDue = false
  @ViewState private var due = Date()
  @ViewState private var snoozed = false
  @ViewState private var retainedSnooze: String?
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text("编辑事项").font(UIType.heading).accessibilityAddTraits(.isHeader)
        Text(row.subject).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(2)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Palette.paper)
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 20) {
          WorkflowField(title: "行动") {
            WorkflowTextInput(label: "行动标题", placeholder: "行动标题", text: $title)
          }
          WorkflowField(title: "状态") {
            WorkflowSelection(
              title: "跟进状态", selection: $state,
              options: [("mine", "待我处理"), ("waiting", "等待对方"), ("completed", "已完成")]
            )
            .frame(width: Self.fieldWidth)
          }
          CossSeparator()
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
              timingToggle("跟进提醒", icon: .bell, enabled: $hasDue)
              timingToggle("稍后处理", icon: .clock, enabled: Binding(get: { snoozed }, set: {
                snoozed = $0
                retainedSnooze = nil
              }), detail: retainedSnooze == nil ? "\(Self.snoozeMinutes) 分钟" : nil)
            }
            if hasDue {
              FollowUpDateTimeField(title: "跟进时间", date: $due).frame(width: Self.fieldWidth)
            }
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
      hasDue = item.followUp?.dueAt != nil
      due = item.followUp?.dueAt.flatMap(MailTimestamp.date) ?? FollowUpHour.next(after: .now)
      retainedSnooze = item.followUp?.isSnoozed == true ? item.followUp?.snoozedUntil : nil
      snoozed = retainedSnooze != nil || startSnoozed
    }
  }
  private func timingToggle(_ title: String, icon: AppicaGlyph, enabled: Binding<Bool>, detail: String? = nil) -> some View {
    Toggle(isOn: enabled) {
      HStack(spacing: 8) {
        AppicaIcon(icon).frame(width: 16).foregroundStyle(Palette.muted).accessibilityHidden(true)
        Text(title)
        if let detail {
          Text(detail).font(UIType.caption).foregroundStyle(Palette.muted).accessibilityHidden(true)
        }
      }
    }.toggleStyle(CossToggleStyle(isSwitch: true)).controlSize(.small).tint(Palette.accent).frame(height: 32)
      .accessibilityLabel(title).accessibilityHint(detail ?? "")
  }
  private func save() {
    let snoozedUntil = snoozed ? retainedSnooze ?? ISO8601DateFormatter().string(
      from: Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60))) : nil
    Task {
      if await workspace.update(item, in: row,
        [
          "title": title, "state": state,
          "dueAt": hasDue ? ISO8601DateFormatter().string(from: due) as Any : NSNull(),
          "snoozedUntil": snoozedUntil as Any? ?? NSNull(),
        ]) != nil
      {
        dismiss()
      }
    }
  }
}
