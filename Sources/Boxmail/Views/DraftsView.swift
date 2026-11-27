import BoxmailCore
import SwiftUI

struct DraftsView: View {
  @Bindable var store: MailStore
  @ViewState<MailDraft?> private var deletingDraft = nil
  @ViewState private var adjustingPlan: SendPlan?
  @ViewState private var scheduledAt = Date()
  private var drafts: [MailDraft] { store.drafts.filter { $0.accountId == store.accountId } }
  var body: some View {
    let currentPlans = store.sendQueue.currentPlans
    OverlayScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HStack {
          PageHeading(title: "草稿箱", subtitle: "自动保存在本机，随邮箱同步服务器；同时编辑时保留双方副本")
          Spacer()
          ActionButton(title: store.busy.contains("sync") ? "同步中…" : "同步草稿", icon: .refresh) {
            Task { await store.syncAll(folder: "drafts") }
          }.disabled(store.busy.contains("sync") || store.currentAccount?.isDemo != false)
          ActionButton(title: "新建邮件", icon: .edit, emphasis: .primary) {
            store.newDraft()
          }
        }.padding(.bottom, 6)
        if let error = store.sendQueue.error {
          WorkflowNotice(text: error, icon: .infoCircle, color: Palette.amber)
        }
        Text("\(drafts.count) 份草稿").font(UIType.caption).foregroundStyle(Palette.muted)
        ForEach(drafts) { draft in
          let plan = currentPlans[draft.id].flatMap { $0.accountId == draft.accountId ? $0 : nil }
          let uncertain = draft.status == "uncertain" || plan?.status == "uncertain"
          let submitting = draft.status == "sending" || plan?.status == "submitting"
          let preview = draft.preview ?? ""
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
              AppicaIcon(.fileText).foregroundStyle(Palette.muted).frame(
                width: 22, height: 22)
              VStack(alignment: .leading, spacing: 6) {
                Text(draft.subject.isEmpty ? "无主题草稿" : draft.subject).font(
                  .system(size: 14, weight: .semibold)
                ).lineLimit(2)
                Text("收件人：\(draft.to.isEmpty ? "未填写" : draft.to)").font(.system(size: 11))
                  .foregroundStyle(Palette.muted).lineLimit(1)
              }
              Spacer(minLength: 8)
              Text(displayTime(draft.updatedAt)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Palette.muted)
            }
            Text(preview.isEmpty ? "尚未撰写正文" : preview)
            .font(UIType.body).foregroundStyle(Palette.muted).lineLimit(2).lineSpacing(4)
            .frame(maxWidth: UILayout.document, alignment: .leading)
            if let issue = draft.syncError {
              WorkflowNotice(text: issue, icon: .infoCircle, color: Palette.amber)
            }
            if let plan { deliveryWarnings(plan) }
            let status = draftStatus(draft, plan: plan, uncertain: uncertain)
            let actions = draftActions(draft, plan: plan, uncertain: uncertain, submitting: submitting)
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 8) {
                status.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                actions
              }
              VStack(alignment: .leading, spacing: 4) {
                status
                actions.frame(maxWidth: .infinity, alignment: .trailing)
              }
            }
          }.padding(UILayout.sectionInset).frame(maxWidth: .infinity, alignment: .leading)
            .framedSurface()
        }
        if drafts.isEmpty {
          EmptyState(title: "还没有草稿", subtitle: "点击写邮件开始，AI 也可以帮你拟稿。", icon: .edit)
            .frame(height: 350)
        }
      }.workspacePage()
    }.background(Palette.canvas)
      .task { await store.sendQueue.load() }
      .cossAlert("删除草稿？", isPresented: Binding(get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } }), presenting: deletingDraft) { draft in
        CossAlertAction("取消", role: .cancel) { deletingDraft = nil }
        CossAlertAction("删除草稿", role: .destructive) {
          deletingDraft = nil
          store.action("delete-draft") { try await store.backend.perform("/drafts/\(draft.id)", method: "DELETE") }
        }
      } message: { _ in
        Text("删除本机草稿，并在下次成功同步时清理对应的服务器草稿。")
      }
      .sheet(item: $adjustingPlan) { plan in
        VStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 20) {
            Text("调整发送时间").font(UIType.heading)
            SendScheduleForm(date: $scheduledAt)
          }.padding(24)
          SettingsActionBar(primaryTitle: "保存时间", cancel: { adjustingPlan = nil }, primary: {
            changePlan(plan, date: scheduledAt)
          }) { EmptyView() }
          .disabled(changingPlan)
        }.frame(width: CossDatePickerLayout.cell * 7 + UILayout.pageInset * 2).background(Palette.paper)
      }
  }
  private var changingPlan: Bool { store.busy.contains("draft-plan") || store.busy.contains("draft-load") }

  private func changePlan(_ plan: SendPlan, date: Date? = nil, cancel: Bool = false) {
    store.action("draft-plan") {
      try await store.sendQueue.change(plan, date: date, cancel: cancel)
      adjustingPlan = nil
    }
  }

  private func draftStatus(_ draft: MailDraft, plan: SendPlan?, uncertain: Bool) -> some View {
    HStack(spacing: 8) {
      Text(syncTitle(draft)).fixedSize()
        .foregroundStyle(draft.syncState == "conflict" ? Palette.amber : Palette.muted)
      if let plan {
        CossSeparator(axis: .vertical).frame(height: 12)
        deliveryStatus(plan).layoutPriority(1)
      }
      if uncertain && plan?.status != "uncertain" {
        Label("发送结果待确认", icon: .infoCircle).foregroundStyle(Palette.amber)
      }
      if !draft.attachmentIds.isEmpty {
        Label("\(draft.attachmentIds.count) 个附件", icon: .paperclip).foregroundStyle(Palette.muted)
      }
    }.font(UIType.small)
  }

  private func draftActions(_ draft: MailDraft, plan: SendPlan?, uncertain: Bool, submitting: Bool) -> some View {
    let editing = store.composer?.id == draft.id
    return HStack(spacing: 8) {
      if draft.syncState == "conflict" && plan == nil && draft.status == "draft" {
        ActionButton(title: "同步副本", icon: .refresh) {
          store.action("resume-draft-sync") {
            let full: MailDraft = try await store.backend.request("/drafts/\(draft.id)")
            let _: MailDraft = try await store.backend.request("/drafts", method: "POST", body: try jsonObject(full))
            await store.syncAll(folder: "drafts", accountID: draft.accountId)
          }
        }.disabled(editing || changingPlan || store.busy.contains("sync") || store.busy.contains("resume-draft-sync"))
      }
      if let plan, plan.canChange {
        ActionButton(title: "取消发送") { changePlan(plan, cancel: true) }.disabled(editing || changingPlan)
        ActionButton(title: "改期") {
          scheduledAt = MailTimestamp.date(plan.scheduledAt) ?? Date()
          adjustingPlan = plan
        }.disabled(editing || changingPlan)
      } else if draft.status == "draft" && !submitting && !uncertain {
        IconButton(icon: .trash, help: "删除草稿") { deletingDraft = draft }.disabled(editing || changingPlan)
      }
      ActionButton(title: editing ? "返回写信" : uncertain ? "查看草稿" : "继续编辑", icon: .edit) {
        store.editDraft(draft.id)
      }.disabled(submitting || changingPlan || (store.composer != nil && !editing))
    }.fixedSize(horizontal: true, vertical: false)
  }

  private func deliveryStatus(_ plan: SendPlan) -> some View {
    let date = MailTimestamp.date(plan.scheduledAt)
    let zone = TimeZone(identifier: plan.timeZone) ?? .current
    let format = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
    let title = "\(WorkspaceStatus.title(plan.status)) · \(date?.formatted(format) ?? plan.scheduledAt) · \(zone.identifier)"
    return Label(title, icon: .clock).monospacedDigit().lineLimit(1).truncationMode(.middle).cossTooltip(title)
      .foregroundStyle(plan.status == "failed" || plan.status == "uncertain" ? Palette.amber : Palette.muted)
  }

  @ViewBuilder private func deliveryWarnings(_ plan: SendPlan) -> some View {
    let rejected = plan.rejected.flatMap { $0.isEmpty ? nil : "未接受：" + $0.joined(separator: ", ") }
    let messages = [plan.error, plan.warning, rejected].compactMap { $0 }.filter { !$0.isEmpty }
    if !messages.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(messages.indices, id: \.self) { index in Text(messages[index]) }
      }
      .font(UIType.caption).foregroundStyle(Palette.amber)
    }
  }
  private func syncTitle(_ draft: MailDraft) -> String {
    switch draft.syncState {
    case "synced": return "已同步服务器"
    case "pending": return "等待同步服务器"
    case "conflict": return "需要处理同步冲突"
    default: return "本机草稿"
    }
  }
}
