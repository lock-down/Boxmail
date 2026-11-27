import BoxmailCore
import SwiftUI

struct RuleManagementView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: RuleWorkspaceStore
  @ViewState private var editing: MailRule?
  @ViewState private var inspection: RuleRun?
  @ViewState private var sourceId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let error = workspace.error { WorkflowNotice(text: error, color: Palette.amber) }
      if workspace.rules.isEmpty {
        EmptyState(
          title: "还没有整理规则", subtitle: "到待办清单的「整理助手」创建规则。", icon: .filter2)
      } else {
        ForEach(workspace.rules) { rule in
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
              ).toggleStyle(CossToggleStyle(isSwitch: true)).controlSize(.mini)
            }
            if !rule.intent.isEmpty {
              Text(rule.intent).font(UIType.caption).foregroundStyle(Palette.muted)
            }
            Text(
              "\(rule.query.accountId.flatMap { id in store.accounts.first { $0.id == id }?.email } ?? "所有账户") · \(rule.query.folder == "all" ? "所有文件夹" : MailDestination(rawValue: rule.query.folder)?.title ?? rule.query.folder) · \(rule.query.query)"
            )
            .font(UIType.small).foregroundStyle(Palette.muted)
            Text(rule.actions.description).font(UIType.caption)
            if rule.actions.includesAI {
              WorkflowNotice(text: rule.automaticPauseReason ?? "移除旧 AI 动作后可运行此规则。", color: Palette.amber)
            }
            HStack {
              Label(
                rule.automatic ? "收到新邮件时运行" : "手动运行",
                icon: rule.automatic ? .refresh : .pointer
              )
              .font(UIType.small).foregroundStyle(Palette.muted)
              Spacer()
              ActionButton(title: "预览匹配", color: Palette.accent, emphasis: .tinted) {
                Task {
                  if let run = await workspace.preview(rule) { inspection = run }
                }
              }.disabled(rule.actions.includesAI)
              ActionButton(title: "编辑") { editing = rule }
              IconButton(icon: .trash, help: "移除此规则") { Task { await workspace.remove(rule) } }
            }
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous))
            .accessibilityElement(children: .contain)
        }
      }
    }.task { await workspace.loadRules() }
      .sheet(item: $editing) { rule in
        RuleEditor(store: store, workspace: workspace, initial: rule).workspaceWindowSize(.settings)
      }
      .sheet(item: $inspection, onDismiss: {
        if sourceId != nil { store.showSettings = false }
      }) { run in
        RuleRunDetailsView(workspace: workspace, initial: run) { id in
          sourceId = id
          inspection = nil
        }
      }
      .onDisappear {
        if let sourceId { store.openSourceMessage(sourceId) }
      }
  }
}

struct RuleRunDetailsView: View {
  @Bindable var workspace: RuleWorkspaceStore
  let initial: RuleRun
  let openSource: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  private var run: RuleRun { workspace.runs.first { $0.id == initial.id } ?? initial }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(run.name).font(UIType.heading).accessibilityAddTraits(.isHeader)
        Spacer()
        IconButton(icon: .x, help: "关闭处理记录") { dismiss() }
      }
      Text(run.actions.description).font(UIType.caption)
      HStack {
        if !run.actions.includesAI && ["preview", "failed", "partial", "paused"].contains(run.status) {
          ActionButton(
            title: run.status == "preview" ? "确认运行" : "重试剩余", color: Palette.accent,
            emphasis: .tinted
          ) { Task { await workspace.run(run) } }
          .disabled(run.items.isEmpty)
        }
        if run.status == "running" {
          ActionButton(title: "暂停处理") { Task { await workspace.pause(run) } }
        }
        if ["completed", "partial", "paused"].contains(run.status) {
          ActionButton(title: "撤销变更") { Task { await workspace.undo(run) } }
        }
        Text(WorkspaceStatus.title(run.status)).font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let error = workspace.error ?? run.error { Text(error).font(UIType.caption).foregroundStyle(Palette.amber) }
      WorkspaceList(items: run.items, header: { EmptyView() }, footer: { EmptyView() }) { item in
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
          ActionButton(title: "原邮件") { openSource(item.id) }
          ForEach(item.suggestions) { todo in
            Text(AITextStyle.inline(todo.title)).font(UIType.caption)
          }
          ForEach(item.jobIds, id: \.self) { id in
            if let job = workspace.jobs[id].flatMap({ $0.task == "reply" ? $0 : nil }),
              let body = job.result?.body
            {
              DisclosureGroup("回复预览") {
                AnalysisDocumentView(text: body)
              }
            }
          }
        }.padding(16)
      }
    }.padding(20).frame(width: 600, height: 420).background(Palette.paper)
      .task(id: "\(run.id)-\(run.status)") {
        await workspace.loadJobs(for: run)
        while run.status == "running" && !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(2)) } catch { return }
          await workspace.loadActivity()
        }
      }
  }
}
