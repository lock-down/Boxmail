import BoxmailCore
import SwiftUI

struct ChecklistView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: FollowUpStore
  @ViewState private var editing: EditRequest?
  @ViewState private var showsMailPicker = false
  @ViewState private var showsPolicy = false
  @ViewState private var policy: MailOrganizationPolicy?
  @ViewState private var policyRevision = 0

  private var policyAccountID: String { store.unifiedInbox ? "" : store.accountId }

  private struct EditRequest: Identifiable {
    let row: ChecklistRow
    let item: ChecklistItem
    var snooze = false
    var id: String { item.id }
  }

  private var request: ChecklistRequest {
    .init(accountId: store.unifiedInbox ? "" : store.accountId, unified: store.unifiedInbox,
      filter: workspace.filter, offset: workspace.pages.offset, followUpId: workspace.reveal?.followUpId)
  }

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 16) {
        WorkspaceHeader(title: "清单", subtitle: "") { toolbar }
        if let policy, policy.id == policyAccountID, store.currentAccount?.isDemo == false,
          policy.mode == "undecided", !store.dismissedOrganizationPrompts.contains(policy.id) {
          consentNotice(policy)
        } else if let policy, policy.id == policyAccountID, policy.mode == "automatic", policy.point == nil {
          Text("等待连接邮箱以建立新信起点").font(UIType.caption).foregroundStyle(Palette.muted)
        }
        if let error = workspace.error ?? store.summaryListError {
          WorkflowNotice(text: error, color: Palette.destructive)
        }
        if let change = store.summaryListChange {
          feedback(change.hidden ? "已移除摘要" : "已恢复摘要", undo: store.undoSummaryListChange) {
            store.summaryListChange = nil
          }
        }
        if let item = workspace.dismissedItem {
          feedback("已将事项标为无需处理", undo: {
            Task {
              if await workspace.save(["dismissed": false], id: item.id) != nil {
                workspace.dismissedItem = nil
              }
            }
          }) { workspace.dismissedItem = nil }
        }
        checklist
      }
      .task(id: RefreshKey(request: request, revision: workspace.revision)) {
        let requested = request
        await load(requested)
        guard !Task.isCancelled, let reveal = workspace.reveal,
          reveal.followUpId == requested.followUpId, workspace.pages.error == nil,
          let page = workspace.pages.page else { return }
        workspace.reveal = nil
        guard let id = page.targetFollowUpId, let row = page.rows.first(where: { row in
          row.items.contains { $0.followUp?.id == id }
        }), let item = row.items.first(where: { $0.followUp?.id == id }) else {
          workspace.error = "该清单事项已变更或移除。"
          return
        }
        workspace.selectedId = id
        if reveal.edit { editing = .init(row: row, item: item, snooze: reveal.snooze) }
      }
      .onChange(of: workspace.selectedId) { _, id in
        if let id { proxy.scrollTo(id, anchor: .center) }
      }
    }
    .sheet(item: $editing) { request in
      FollowUpEditor(workspace: workspace, row: request.row, item: request.item, startSnoozed: request.snooze)
        .workspaceSheet(.categories)
    }
    .sheet(isPresented: $showsMailPicker) { OrganizationMailPicker(store: store, label: nil) }
    .sheet(isPresented: $showsPolicy) {
      OrganizationPolicyView(store: store, initialAccountID: policyAccountID) { policyRevision += 1 }
    }
    .task(id: "\(policyAccountID)-\(policyRevision)-\(store.restoreRevision)") {
      let account = policyAccountID
      policy = nil
      guard !account.isEmpty else { return }
      while !Task.isCancelled {
        guard let result = try? await store.organizationPolicy(for: account), !Task.isCancelled else { return }
        policy = result
        guard result.mode == "automatic", result.point == nil else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
    .workspacePage().background(Palette.paper)
  }

  private func consentNotice(_ policy: MailOrganizationPolicy) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text("自动整理这个邮箱的新邮件？").font(UIType.section)
        Spacer()
        IconButton(icon: .x, help: "关闭自动整理提示") {
          store.dismissedOrganizationPrompts.insert(policy.id)
        }
      }
      Text("新邮件的主题和正文会提交给已配置的 AI 服务商，用于生成摘要和待办。启用标签匹配时也会提交发件人和已启用的条件。费用按服务商计收。")
        .font(UIType.caption).foregroundStyle(Palette.muted)
      HStack {
        ActionButton(title: "开启自动整理", emphasis: .primary, size: .compact) { showsPolicy = true }
        ActionButton(title: "仅手动整理", emphasis: .secondary, size: .compact) {
          Task {
            do { _ = try await store.saveOrganizationPolicy(["accountId": policy.id, "mode": "manual"]); policyRevision += 1 }
            catch { workspace.error = error.localizedDescription }
          }
        }
      }
    }.padding(12).framedSurface()
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      CossMenu(title: "筛选清单", value: workspace.filter.title, emphasis: .secondary, prefersSelection: true) {
        for filter in ChecklistFilter.allCases where filter != .removed {
          CossMenuItem.command(filter.title, mark: .choice(workspace.filter == filter)) {
            workspace.setFilter(filter)
          }
        }
      } trigger: {
        CossMenuLabel(title: workspace.filter == .removed ? "全部" : workspace.filter.title, icon: .filter2)
      }
      ActionButton(title: "整理邮件…", emphasis: .secondary, size: .compact) { showsMailPicker = true }
        .disabled(store.accounts.isEmpty)
      IconMenu(icon: .dots, help: "清单菜单") {
        CossMenuItem.command("新邮件自动整理…", enabled: store.accounts.contains { !$0.isDemo }) { showsPolicy = true }
        CossMenuItem.command("已移除摘要", mark: .choice(workspace.filter == .removed)) {
          workspace.setFilter(.removed)
        }
        CossMenuItem.divider
        CossMenuItem.command("提醒设置", icon: .bell) {
          store.settingsTab = "常用"
          store.showSettings = true
        }
      }
    }
  }

  @ViewBuilder private var checklist: some View {
    if let error = workspace.pages.error {
      PageStoreErrorRow(error: error, canRestore: false, restore: {}) {
        Task { await load(request, force: true) }
      }
    }
    if let page = workspace.pages.page, workspace.pages.loadedRequest?.sameFilters(as: request) == true {
      if page.rows.isEmpty {
        EmptyState(title: workspace.filter == .removed ? "没有已移除的摘要" : "没有符合条件的邮件",
          subtitle: workspace.filter == .all ? "也可以从邮件菜单手工加入事项。" : "", icon: .listCheck,
          actionTitle: workspace.filter == .all ? "整理邮件…" : nil, actionDisabled: store.accounts.isEmpty) {
          showsMailPicker = true
        }
      } else {
        WorkspaceList(items: page.rows, scrollPosition: workspace.scrollPosition) {
          if workspace.filter == .removed {
            Text(workspace.filter.title).font(UIType.section)
              .frame(maxWidth: .infinity, alignment: .leading).padding(16)
              .accessibilityAddTraits(.isHeader)
            CossSeparator()
          }
        } footer: {
          ListPagination(offset: page.offset, count: page.rows.count, total: page.total, limit: page.limit,
            unit: "封", subject: "清单邮件", loading: workspace.pages.loading) {
            workspace.scrollPosition.origin = .zero
            workspace.pages.goPrevious()
          } next: {
            workspace.scrollPosition.origin = .zero
            workspace.pages.goNext()
          }
        } row: { row in
          sourceRow(row)
        }
        .id(page.offset)
      }
    } else if workspace.pages.error == nil {
      CossSpinner(size: 20).accessibilityLabel("正在加载清单")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func sourceRow(_ row: ChecklistRow) -> some View {
    let subject = row.subject.isEmpty ? "无主题" : row.subject
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if row.hasSource {
          Button { store.openSourceMessage(row.messageId) } label: {
            Text(subject).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          }.buttonStyle(.plain).foregroundStyle(Palette.accent).controlFocus()
            .accessibilityHint("打开原邮件")
        } else {
          Text(subject).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if row.summary != nil {
          if row.summaryHidden {
            ActionButton(title: "恢复摘要", emphasis: .secondary, size: .compact) {
              store.setSummaryVisibility(ids: [row.messageId], hidden: false, for: row.accountId)
            }.disabled(store.busy.contains("summary-list-\(row.accountId)"))
          } else {
            IconMenu(icon: .dots, help: "摘要操作") {
              CossMenuItem.command("移除摘要") {
                store.setSummaryVisibility(ids: [row.messageId], hidden: true, for: row.accountId)
              }
            }.disabled(store.busy.contains("summary-list-\(row.accountId)"))
          }
        }
      }.font(UIType.section).accessibilityAddTraits(.isHeader)
      let source = sourceDetails(row)
      if !source.isEmpty {
        Text(source).font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
      if let summary = row.summary {
        Text(AITextStyle.preview(summary.overviewText)).font(UIType.body).lineLimit(3)
          .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
      if !row.items.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(row.items) { item in
            actionRow(item, in: row).id(item.followUp?.id ?? item.id)
          }
        }.padding(.top, 2)
      }
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
  }

  private func sourceDetails(_ row: ChecklistRow) -> String {
    let account = store.unifiedInbox ? store.accounts.first { $0.id == row.accountId }?.sidebarName : nil
    let date = MailTimestamp.date(row.date)?.formatted(date: .abbreviated, time: .shortened)
    return [row.sender, account, date, row.hasSource ? nil : "来源邮件已不可用"]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private func actionRow(_ item: ChecklistItem, in row: ChecklistRow) -> some View {
    let completed = item.state == "completed"
    let selected = item.followUp.map { $0.id == workspace.selectedId } ?? false
    return HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Toggle(isOn: Binding(get: { completed }, set: { checked in
          Task { await workspace.update(item, in: row, ["state": checked ? "completed" : "mine"]) }
        })) {
          Text(AITextStyle.inline(item.title)).strikethrough(completed)
            .foregroundStyle(completed ? Palette.muted : Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
        }.toggleStyle(CossToggleStyle())
        if let detail = actionDetails(item) {
          Text(detail).font(UIType.small).foregroundStyle(item.followUp?.isDue == true ? Palette.amber : Palette.muted)
            .fixedSize(horizontal: false, vertical: true).padding(.leading, 24)
        }
        if let reply = item.followUp?.replyMessageId {
          ActionButton(title: "已收到回复", icon: .arrowBackUp, color: Palette.accent, size: .compact) {
            store.openSourceMessage(reply)
          }.padding(.leading, 16)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
      IconMenu(icon: .dots, help: "事项操作：\(item.title)") {
        CossMenuItem.command("编辑事项…", icon: .edit) { editing = .init(row: row, item: item) }
        if !completed {
          CossMenuItem.command(item.state == "waiting" ? "转为待我处理" : "等待对方") {
            Task { await workspace.update(item, in: row, ["state": item.state == "waiting" ? "mine" : "waiting"]) }
          }
          if item.followUp?.isSnoozed == true {
            CossMenuItem.command("取消延后") { Task { await workspace.update(item, in: row, ["snoozedUntil": NSNull()]) } }
          } else {
            CossMenuItem.command("延后…", icon: .clock) { editing = .init(row: row, item: item, snooze: true) }
          }
          if item.followUp?.effectiveDate != nil, item.followUp?.reminderCancelled == false {
            CossMenuItem.command("取消本次提醒") { Task { await workspace.update(item, in: row, ["cancelReminder": true]) } }
          }
        }
        if item.todoId != nil {
          CossMenuItem.divider
          CossMenuItem.command("无需处理") {
            Task { workspace.dismissedItem = await workspace.update(item, in: row, ["dismissed": true]) }
          }
        } else if let followUp = item.followUp {
          CossMenuItem.divider
          CossMenuItem.command("移除事项", destructive: true) { Task { await workspace.remove(followUp) } }
        }
      }
    }.font(UIType.body).padding(.horizontal, 8)
      .background(selected ? Palette.accentSoft : Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
      .disabled(workspace.isMutating(item, in: row))
  }

  private func actionDetails(_ item: ChecklistItem) -> String? {
    var values: [String] = []
    if item.state == "waiting" && item.followUp?.replyMessageId == nil { values.append("等待对方") }
    if let date = item.followUp?.effectiveDate {
      let prefix = item.followUp?.isSnoozed == true ? "延后至" : "提醒"
      values.append("\(prefix) \(date.formatted(date: .abbreviated, time: .shortened))")
    } else if !item.dueText.isEmpty {
      values.append(item.dueText)
    }
    return values.isEmpty ? nil : values.joined(separator: " · ")
  }

  private func load(_ requested: ChecklistRequest, force: Bool = false) async {
    await workspace.pages.load(requested, revision: workspace.revision, force: force, current: { request })
  }

  private func feedback(_ title: String, undo: @escaping () -> Void, close: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Text(title).font(UIType.caption)
      Spacer(minLength: 0)
      ActionButton(title: "撤销", size: .compact, action: undo)
      IconButton(icon: .x, help: "关闭提示", action: close)
    }.padding(.horizontal, 12).padding(.vertical, 4).framedSurface()
  }
}
