import BoxmailCore
import SwiftUI

struct SendQueueView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: SendQueueStore
  @ViewState private var editing: SendPlan?
  @ViewState private var scheduledAt = Date()
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      WorkspaceHeader(title: "发送管理", subtitle: "查看待发送邮件与投递结果") {
        Text("\(workspace.plans.count) 封").font(UIType.caption).foregroundStyle(Palette.muted)
          .monospacedDigit()
      }
      if let error = workspace.error {
        Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
      }
      if workspace.plans.isEmpty {
        EmptyState(title: "暂无待发送邮件", subtitle: "在写信窗口确认发送或定时发送后，可在这里查看进度与投递结果", icon: "paperplane")
      } else {
        WorkspaceList(
          items: workspace.plans, bordered: false, header: { EmptyView() }, footer: { EmptyView() }
        ) { plan in
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(plan.subject.isEmpty ? "无主题" : plan.subject).font(
                .system(size: 14, weight: .medium))
              Spacer()
              Text(WorkspaceStatus.title(plan.status)).font(UIType.small)
                .foregroundStyle(
                  plan.status == "failed" || plan.status == "uncertain"
                    ? Palette.amber : Palette.muted)
            }
            Text(
              "\(plan.to) · \(store.accounts.first { $0.id == plan.accountId }?.email ?? "来源账户")"
            )
            .font(UIType.caption).foregroundStyle(Palette.muted)
            Text("计划：\(plannedTime(plan)) · \(plan.timeZone)")
              .font(UIType.small).foregroundStyle(Palette.muted)
            if let error = plan.error {
              Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
            }
            if let warning = plan.warning {
              Text(warning).font(UIType.caption).foregroundStyle(Palette.amber)
            }
            if let rejected = plan.rejected, !rejected.isEmpty {
              Text("未接受：" + rejected.joined(separator: ", ")).font(UIType.caption).foregroundStyle(
                Palette.amber)
            }
            HStack {
              if plan.canChange {
                ActionButton(title: "取消并返回草稿", icon: "arrow.uturn.backward") {
                  Task {
                    await workspace.change(plan, cancel: true)
                    guard workspace.error == nil else { return }
                    try? await store.refresh()
                    store.editDraft(plan.draftId)
                  }
                }
                ActionButton(title: "改期") {
                  scheduledAt = MailTimestamp.date(plan.scheduledAt) ?? Date()
                  editing = plan
                }
              } else if plan.status == "uncertain" {
                Text("请先核对已发送邮箱，确认投递结果后再另存草稿。")
                  .font(UIType.small).foregroundStyle(Palette.muted)
                ActionButton(title: "查看草稿") { store.editDraft(plan.draftId) }
              }
            }
          }.padding(20).accessibilityElement(children: .contain)
        }
      }
    }.workspacePage().background(Palette.paper).task { await workspace.load() }
      .sheet(item: $editing) { plan in
        VStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 20) {
            Text("调整发送时间").font(UIType.heading)
            SendScheduleForm(date: $scheduledAt)
          }.padding(24)
          SettingsActionBar(
            primaryTitle: "保存时间", cancel: { editing = nil },
            primary: {
              Task {
                await workspace.change(plan, date: scheduledAt)
                if workspace.error == nil { editing = nil }
              }
            }
          ) {
            EmptyView()
          }
        }.frame(width: 480).background(Palette.paper)
      }
  }
  private func plannedTime(_ plan: SendPlan) -> String {
    guard let date = MailTimestamp.date(plan.scheduledAt) else { return plan.scheduledAt }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.timeZone = TimeZone(identifier: plan.timeZone) ?? .current
    return formatter.string(from: date)
  }
}
