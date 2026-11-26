import BoxmailCore
import SwiftUI

struct ActivityView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<Bool> private var showsHistory = false
  @ViewState private var organization: OrganizationActivity?
  @ViewState private var operationError: String?
  @ViewState private var selectedRun: RuleRun?
  @ViewState private var sourceMessageId: String?

  private struct OrganizationActivity: Decodable {
    let jobs: [AgentJob]
    let usage: [AIUsage]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        PageHeading(title: "活动记录", subtitle: "最近同步结果与任务记录")
        Spacer()
        IconButton(icon: .x, help: "关闭") { dismiss() }
      }
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(store.accounts.filter { !$0.isDemo }) { account in
            accountResult(account)
          }
          if let operationError { WorkflowNotice(text: operationError, color: Palette.destructive) }
          if let organization, !organization.jobs.isEmpty || !organization.usage.isEmpty {
            organizationResults(organization)
          }
          if let error = store.rules.error { WorkflowNotice(text: error, color: Palette.destructive) }
          if !store.rules.runs.isEmpty {
            DisclosureGroup("邮箱规则处理记录") {
              ForEach(store.rules.runs) { run in
                ActionButton(title: run.name, icon: .listDetails) { selectedRun = run }
                Text("\(WorkspaceStatus.title(run.status)) · \(run.items.count) 封 · \(displayTime(run.createdAt))")
                  .font(UIType.small).foregroundStyle(Palette.muted)
              }
            }
          }
          if !store.rules.usage.isEmpty {
            DisclosureGroup("AI 用量") {
              ForEach(store.rules.usage) { usage in usageRow(usage) }
            }
          }
          ForEach(store.events.filter { $0.type != "sync" }) { event in
            eventRow(event)
          }
          if !store.events.filter({ $0.type == "sync" }).isEmpty {
            DisclosureGroup("同步历史记录", isExpanded: $showsHistory) {
              ForEach(ActivityPresentation.history(store.events.filter { $0.type == "sync" })) { entry in
                if entry.events.count > 1 {
                  DisclosureGroup("相同无变化结果 · \(entry.events.count) 次") {
                    ForEach(entry.events) { event in eventRow(event) }
                  }.font(UIType.caption).padding(.vertical, 8)
                } else if let event = entry.events.first {
                  eventRow(event)
                }
              }
            }.font(UIType.caption)
          }
          if store.events.isEmpty && store.accounts.allSatisfy(\.isDemo) && organization?.jobs.isEmpty != false
            && store.rules.runs.isEmpty && store.rules.usage.isEmpty {
            EmptyState(title: "还没有活动记录", subtitle: "同步、AI 任务和发送状态会显示在这里。", icon: .clock)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(24).frame(width: 640, height: 480)
      .sheet(item: $selectedRun, onDismiss: { if sourceMessageId != nil { dismiss() } }) { run in
        RuleRunDetailsView(workspace: store.rules, initial: run) { id in
          sourceMessageId = id
          selectedRun = nil
        }
      }
      .onDisappear {
        if let sourceMessageId { store.openSourceMessage(sourceMessageId) }
      }
      .task {
        while !Task.isCancelled {
          do {
            if selectedRun == nil { await store.rules.loadActivity() }
            organization = try await store.backend.request("/mail-organization/activity", timeout: 8)
            try await Task.sleep(for: .seconds(2))
          } catch is CancellationError { return }
          catch {
            operationError = error.localizedDescription
            return
          }
        }
      }
  }

  private func organizationResults(_ activity: OrganizationActivity) -> some View {
    SectionCard(title: "清单整理", contentSpacing: 10) {
      ForEach(activity.jobs) { job in
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            let subject = store.messages.first { $0.id == job.messageId }?.subject
            Text(subject ?? "来源邮件").font(UIType.body).lineLimit(2)
            let state = ["pending": "等待整理", "running": "正在整理", "completed": "已整理", "failed": "整理失败", "paused": "已暂停"]
            Text(job.error ?? state[job.status] ?? job.status).font(UIType.caption).foregroundStyle(Palette.muted)
          }
          Spacer()
          if ["failed", "paused"].contains(job.status) {
            ActionButton(title: "重试", icon: .refresh, size: .compact) {
              Task {
                do {
                  try await store.backend.perform("/mail-organization/retry", body: ["id": job.id])
                  organization = try await store.backend.request("/mail-organization/activity")
                  operationError = nil
                } catch { operationError = error.localizedDescription }
              }
            }
          }
        }
      }

    }
  }

  private func usageRow(_ usage: AIUsage) -> some View {
    let input = usage.input.map { String(Int($0)) } ?? "未知"
    let output = usage.output.map { String(Int($0)) } ?? "未知"
    let cached = usage.cacheRead.map { String(Int($0)) } ?? "未知"
    let written = usage.cacheWrite.map { String(Int($0)) } ?? "未知"
    return VStack(alignment: .leading, spacing: 4) {
      Text("\(ActivityPresentation.taskTitle(usage.task)) · \(usage.model)").font(UIType.body)
      Text("\(usage.provider) · \(WorkspaceStatus.title(usage.status)) · \(displayTime(usage.startedAt))")
      Text("输入 \(input) · 输出 \(output) · 缓存读取 \(cached) · 写入 \(written) · \(usage.durationMs) ms")
      if let job = store.jobs.first(where: { $0.id == usage.taskId }), let id = job.messageId {
        ActionButton(title: "来源邮件", icon: .mail, size: .compact) {
          sourceMessageId = id
          dismiss()
        }
      }
    }.font(UIType.caption).foregroundStyle(Palette.muted)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
  }

  private func accountResult(_ account: MailAccount) -> some View {
    let running = store.syncingAccountIds.contains(account.id)
      || store.syncSnapshot?.runningAccounts.contains(account.id) == true
    let result = store.syncSnapshot?.results.first { $0.accountId == account.id }
    let folders = store.syncSnapshot?.folders.filter { $0.accountId == account.id } ?? []
    let unfinished = folders.filter { $0.status == "failed" || $0.hasMore == true || $0.status == "paused" }
    let latest = store.events.first { ActivityPresentation.syncAccount($0, accounts: [account]) != nil }
    return VStack(alignment: .leading, spacing: 8) {
      Label(account.email, icon: running ? .refresh
        : result?.status == "failed" || !unfinished.isEmpty ? .infoCircle : .clock)
        .font(UIType.caption)
      if running {
        Text("正在同步").font(UIType.small).foregroundStyle(Palette.accent)
      } else if let error = result?.error, !error.isEmpty {
        Text("最近同步未完成：\(error)").font(UIType.small).foregroundStyle(Palette.amber).textSelection(.enabled)
      }
      if !running, !unfinished.isEmpty {
        ForEach(unfinished) { folder in
          Text("\(MailDestination.title(forFolder: folder.folder) ?? folder.folder)：\(folder.lastError ?? "仍有邮件待同步")")
            .font(UIType.small).foregroundStyle(Palette.amber).textSelection(.enabled)
        }
      }
      if let latest {
        Text("最近结果：\(latest.detail.dropFirst(account.email.count + 1))").font(UIType.caption).textSelection(.enabled)
        Text(displayTime(latest.time)).font(UIType.small).foregroundStyle(Palette.muted)
      } else if !running {
        Text("暂无同步结果").font(UIType.small).foregroundStyle(Palette.muted)
      }
      CossSeparator()
    }.accessibilityElement(children: .contain)
  }

  private func eventRow(_ event: AuditEvent) -> some View {
    HStack(alignment: .top, spacing: 8) {
      AppicaIcon(ActivityPresentation.icon(event)).frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(ActivityPresentation.title(event)).font(UIType.caption).textSelection(.enabled)
        Text(displayTime(event.time)).font(UIType.small).foregroundStyle(Palette.muted)
      }
      Spacer(minLength: 0)
    }.foregroundStyle(event.type == "send-warning" ? Palette.amber : Palette.ink)
      .padding(.vertical, 8)
  }
}
