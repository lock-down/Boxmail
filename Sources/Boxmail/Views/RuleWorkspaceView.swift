import BoxmailCore
import SwiftUI

struct RuleWorkspaceView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: RuleWorkspaceStore
  private var tab: String {
    get { workspace.tab }
    nonmutating set { workspace.tab = newValue }
  }
  @ViewState private var editing: MailRule?
  private var selectedRun: RuleRun? { workspace.runs.first { $0.id == workspace.selectedRunId } }
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      WorkspaceHeader(title: "规则与用量", subtitle: "按条件整理邮件，查看处理结果与模型用量") {
        if tab == "规则" && !workspace.rules.isEmpty {
          ActionButton(title: "新建规则", icon: "plus", color: Palette.accent, emphasis: .tinted) {
            editing = MailRule(accountId: store.accountId)
          }
        }
      }
      FilterBar(values: ["规则", "处理记录", "AI 用量"], selection: $workspace.tab)
      if let error = workspace.error {
        Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
      }
      if tab == "规则" {
        if workspace.rules.isEmpty {
          EmptyState(
            title: "还没有整理规则", subtitle: "为常见邮件设置条件和动作，保存后先预览匹配结果",
            icon: "line.3.horizontal.decrease", actionTitle: "新建规则"
          ) { editing = MailRule(accountId: store.accountId) }
        } else {
          WorkspaceList(
            items: workspace.rules, bordered: false, header: { EmptyView() },
            footer: { EmptyView() }
          ) {
            rule in
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text(rule.name).font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle(
                  "启用",
                  isOn: Binding(
                    get: { rule.enabled },
                    set: { value in
                      var updated = rule
                      updated.enabled = value
                      Task { _ = await workspace.save(updated) }
                    })
                ).toggleStyle(.switch).controlSize(.mini)
              }
              if !rule.intent.isEmpty {
                Text(rule.intent).font(UIType.caption).foregroundStyle(Palette.muted)
              }
              Text(
                "\(rule.query.accountId.flatMap { id in store.accounts.first { $0.id == id }?.email } ?? "所有账户") · \(MailDestination(rawValue: rule.query.folder)?.title ?? rule.query.folder) · \(rule.query.query)"
              )
              .font(UIType.small).foregroundStyle(Palette.muted)
              Text(rule.actions.description).font(UIType.caption)
              HStack {
                Label(
                  rule.automatic ? "收到新邮件时运行" : "手动运行",
                  systemImage: rule.automatic ? "arrow.triangle.2.circlepath" : "cursorarrow"
                )
                .font(UIType.small).foregroundStyle(Palette.muted)
                Spacer()
                ActionButton(title: "预览匹配", color: Palette.accent, emphasis: .tinted) {
                  Task {
                    await workspace.preview(rule)
                    tab = "处理记录"
                  }
                }
                ActionButton(title: "编辑") { editing = rule }
                IconButton(icon: "trash", help: "移除此规则") { Task { await workspace.remove(rule) } }
              }
            }.padding(20).accessibilityElement(children: .contain)
          }
        }
      } else if tab == "处理记录" {
        if workspace.runs.isEmpty {
          EmptyState(
            title: "暂无处理记录", subtitle: "预览或运行规则后，可以在这里核对每封邮件的处理结果", icon: "list.bullet.rectangle")
        } else {
          HSplitView {
            List(workspace.runs, selection: $workspace.selectedRunId) { run in
              VStack(alignment: .leading, spacing: 8) {
                Text(run.name).font(UIType.section)
                Text("\(WorkspaceStatus.title(run.status)) · \(run.items.count) 封").font(
                  UIType.small
                ).foregroundStyle(Palette.muted)
              }.padding(.vertical, 8).tag(run.id)
            }.listStyle(.plain).frame(minWidth: 200, idealWidth: 250, maxWidth: 330)
            if let run = selectedRun {
              runDetails(run).frame(minWidth: 360, maxWidth: .infinity)
            } else {
              EmptyState(
                title: "选择处理记录", subtitle: "预览、逐封结果和实际失败原因会保留在这里。", icon: "list.bullet.rectangle")
            }
          }
        }
      } else {
        if workspace.usage.isEmpty {
          EmptyState(
            title: "暂无 AI 用量", subtitle: "使用摘要、附件理解或 AI 写作后，会显示模型调用和用量记录", icon: "chart.bar.xaxis")
        } else {
          WorkspaceList(
            items: workspace.usage, bordered: false, header: { EmptyView() },
            footer: { EmptyView() }
          ) {
            usage in
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("\(ActivityPresentation.taskTitle(usage.task)) · \(usage.model)").font(
                  .system(size: 14, weight: .medium))
                Spacer()
                Text(WorkspaceStatus.title(usage.status)).font(UIType.small).foregroundStyle(
                  Palette.muted)
              }
              Text("\(usage.provider) · \(displayTime(usage.startedAt))").font(UIType.small)
                .foregroundStyle(Palette.muted)
              HStack(spacing: 24) {
                usageMetric("输入", value: tokens(usage.input))
                usageMetric("输出", value: tokens(usage.output))
                usageMetric("缓存读取", value: tokens(usage.cacheRead))
                usageMetric("缓存写入", value: tokens(usage.cacheWrite))
                usageMetric("耗时", value: "\(usage.durationMs) ms")
                Spacer(minLength: 0)
              }
              Text("费用未知 · 未配置可核实价格").font(UIType.small).foregroundStyle(Palette.muted)
              if let job = usage.taskId.flatMap({ id in store.jobs.first { $0.id == id } }),
                let id = job.messageId
              {
                ActionButton(title: "来源邮件") { store.openSourceMessage(id) }
              }
            }.padding(20)
          }
        }
      }
    }.workspacePage().background(Palette.paper)
      .task { await workspace.load() }
      .sheet(item: $editing) { rule in
        RuleEditor(store: store, workspace: workspace, initial: rule).workspaceSheet(.settings)
      }
  }
  private func tokens(_ value: Double?) -> String { value.map { String(Int($0)) } ?? "未知" }
  private func usageMetric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(UIType.small).foregroundStyle(Palette.muted)
      Text(value).font(UIType.caption).monospacedDigit()
    }
  }
  private func runDetails(_ run: RuleRun) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(run.name).font(UIType.heading)
      Text(run.actions.description).font(UIType.caption)
      HStack {
        if ["preview", "failed", "partial", "paused"].contains(run.status) {
          ActionButton(
            title: run.status == "preview" ? "确认运行" : "重试未完成项", color: Palette.accent,
            emphasis: .tinted
          ) { Task { await workspace.run(run) } }
          .disabled(run.items.isEmpty)
        }
        if run.status == "running" {
          ActionButton(title: "暂停后续处理") { Task { await workspace.pause(run) } }
        }
        if ["completed", "partial", "paused"].contains(run.status) {
          ActionButton(title: "撤销邮件状态变更") { Task { await workspace.undo(run) } }
        }
        Text(WorkspaceStatus.title(run.status)).font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let error = run.error { Text(error).font(UIType.caption).foregroundStyle(Palette.amber) }
      WorkspaceList(
        items: run.items, scrollPosition: workspace.scrollPosition, header: { EmptyView() },
        footer: { EmptyView() }
      ) { item in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(item.subject).font(UIType.section)
            Spacer()
            Text(WorkspaceStatus.title(item.status)).font(UIType.small)
          }
          Text(AITextStyle.inline(item.reason)).font(UIType.caption).foregroundStyle(Palette.muted)
          if let error = item.error {
            Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
          }
          ActionButton(title: "原邮件") { store.openSourceMessage(item.id) }
          ForEach(item.suggestions) { todo in
            HStack {
              Text(AITextStyle.inline(todo.title)).font(UIType.caption)
              Spacer()
              ActionButton(title: "收录跟进") {
                if let message = store.messages.first(where: { $0.id == item.id }) {
                  store.collectFollowUp(
                    message: message, todo: todo, sourceKey: "rule:\(run.id):\(todo.id)")
                }
              }
            }
          }
          ForEach(item.jobIds, id: \.self) { id in
            if let job = workspace.jobs[id].flatMap({ $0.task == "reply" ? $0 : nil }),
              let body = job.result?.body
            {
              DisclosureGroup("回复预览") {
                AnalysisDocumentView(text: body)
                ActionButton(title: "使用为草稿") { store.useReply(job) }
              }
            }
          }
        }.padding(16)
      }.listStyle(.plain)
    }.padding(16)
  }
}
