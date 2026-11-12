import BoxmailCore
import SwiftUI

struct OrganizeView: View {
  @Bindable var store: MailStore
  @ViewState<String> private var scope = "unclassified"
  @ViewState<Int> private var limit = 50
  @ViewState private var pages: OrganizationPageStore
  @ViewState<Int> private var reviewOffset = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState<Bool> private var managingCategories = false
  private var categories: [String] { store.categories.map(\.name) }
  var latest: AgentJob? { store.latestOrganization }
  init(store: MailStore) {
    self.store = store
    _pages = ViewState(
      initialValue: OrganizationPageStore(backend: store.backend, accountId: store.accountId))
  }
  private struct RefreshKey: Hashable {
    let request: OrganizationPageRequest
    let revision: Int
  }
  var running: Bool { latest?.status == "running" }
  var hasReview: Bool {
    guard let latest else { return false }
    return ["needsApproval", "partial", "paused"].contains(latest.status)
      && !(latest.result?.items ?? []).isEmpty
  }
  private var streamingOutput: AIStreamOutput? {
    guard running, let job = latest, let output = store.aiOutputs[job.id],
      output.status == "running"
    else {
      return nil
    }
    return output
  }
  private var showsSuggestions: Bool {
    guard let job = latest else { return false }
    return streamingOutput != nil
      || (!(job.result?.items ?? []).isEmpty
        && ["running", "needsApproval", "partial", "paused"].contains(job.status))
  }
  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 720 || running || hasReview
      VStack(alignment: .leading, spacing: compact ? 8 : 22) {
        heading(compact: compact)
        controls(compact: compact)
        if let error = store.organizeError {
          Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12))
            .foregroundStyle(Palette.amber)
        }
        if let job = latest { jobStatus(job, compact: compact) }
        if let job = latest, showsSuggestions {
          reviewSection(job, compact: compact)
        }
        inboxFilters(compact: compact)
        if pages.loading {
          ProgressView("正在加载分类邮件…").controlSize(.small)
        }
        if let error = pages.error {
          HStack {
            Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
            if pages.canRestoreLoadedPage {
              ActionButton(title: "返回上次结果", icon: "arrow.uturn.backward") {
                pages.restoreLoadedPage()
              }
            }
            ActionButton(title: "重试", icon: "arrow.clockwise") {
              Task { await pages.load(revision: store.workspaceListRevision, force: true) }
            }
          }
        }
        if let page = pages.visiblePage {
          if pages.showsPreviousPage {
            Text("保留上次加载的分类邮件").font(UIType.small).foregroundStyle(Palette.muted)
          }
          WorkspaceList(items: page.items) {
            EmptyView()
          } footer: {
            ListPagination(
              offset: page.offset, count: page.items.count, total: page.total, limit: page.limit,
              unit: "封", subject: "分类邮件", loading: pages.loading || pages.showsPreviousPage,
              previous: { pages.previous() }, next: { pages.next() })
          } row: { mail in
            WorkspaceListRow(action: { store.openMail(mail) }) {
              HStack(spacing: 20) {
                Text(mail.sender).font(.system(size: 12, weight: .medium)).lineLimit(1)
                  .frame(width: 130, alignment: .leading)
                Text(mail.subject).font(UIType.caption).lineLimit(1)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Tag(text: mail.category)
                Text(displayTime(mail.date)).font(UIType.small).foregroundStyle(Palette.muted)
                  .frame(width: 80, alignment: .trailing)
              }.foregroundStyle(Palette.ink)
            } actions: {
              EmptyView()
            }
          }
          .id(pages.loadedRequest)
          .opacity(pages.showsPreviousPage ? 0.55 : 1).disabled(pages.showsPreviousPage)
          if page.items.isEmpty {
            Text("这个分类暂时没有邮件").font(UIType.caption).foregroundStyle(Palette.muted)
              .frame(maxWidth: .infinity).padding(30)
          }
        } else {
          Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 16 : UILayout.pageInset)
    }.background(Palette.canvas)
      .sheet(isPresented: $managingCategories) {
        CategoryManagerView(store: store).borderlessScrollers()
      }
      .onChange(of: store.categories) { _, items in
        if !pages.category.isEmpty, !items.contains(where: { $0.name == pages.category }) {
          pages.category = ""
        }
      }
      .onChange(of: store.accountId) { _, id in
        pages.accountId = id
        reviewOffset = 0
      }
      .onChange(of: latest?.id) { _, _ in reviewOffset = 0 }
      .task(id: RefreshKey(request: pages.request, revision: store.workspaceListRevision)) {
        await pages.load(revision: store.workspaceListRevision)
      }
  }
  private func heading(compact: Bool) -> some View {
    HStack(alignment: .top, spacing: 24) {
      if compact {
        Text("智能整理").font(UIType.heading)
        Text(store.currentAccount?.email ?? "当前账户")
          .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          PageHeading(title: "智能整理", subtitle: "按主题整理收件箱，确认建议后再应用分类")
          Label(store.currentAccount?.email ?? "当前账户", systemImage: "tray")
            .font(UIType.small).foregroundStyle(Palette.muted)
        }
      }
      Spacer(minLength: 0)
      WorkflowAction(title: "管理分类", icon: "tag") { managingCategories = true }
        .disabled(running)
    }
  }
  private var scopeSelection: some View {
    WorkflowSelection(
      title: "整理范围", selection: $scope,
      options: [("unclassified", "尚未分类的收件邮件"), ("inbox", "全部收件邮件")])
  }
  private var limitSelection: some View {
    WorkflowSelection(
      title: "邮件数量", selection: $limit,
      options: [10, 50, 100, 200].map { ($0, "最近 \($0) 封") })
  }
  private func controls(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .bottom, spacing: 16) {
        if compact {
          scopeSelection.frame(width: 220)
          limitSelection.frame(width: 136)
        } else {
          WorkflowField(title: "整理范围") { scopeSelection }.frame(width: 220)
          WorkflowField(title: "处理数量") { limitSelection }.frame(width: 136)
        }
        Spacer(minLength: 0)
        WorkflowAction(title: "开始整理", icon: "wand.and.stars", color: Palette.blue) {
          store.organize(scope: scope, limit: limit)
        }.disabled(
          running || hasReview || store.busy.contains("organize-control")
            || (pages.visiblePage?.accountTotal ?? 0) == 0)
      }
      if !compact {
        Text(hasReview ? "先确认已有建议，或继续补齐未完成的邮件。" : "分批在后台分析，整理期间可以继续阅读和回复邮件。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
    }.padding(compact ? 12 : 20).background(
      Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
  }
  private func inboxFilters(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("收件箱分类").font(.system(size: 16, weight: .semibold))
        Spacer()
        if compact {
          WorkflowSelection(
            title: "筛选收件箱分类", selection: $pages.category,
            options: [("", "全部分类")]
              + categories.map { category in
                (
                  category,
                  "\(category)（\(pages.visiblePage?.categoryCounts.first { $0.name == category }?.count ?? 0)）"
                )
              }
          ).frame(width: 200)
        } else if !pages.category.isEmpty {
          Button("查看全部") { pages.category = "" }.buttonStyle(.plain).foregroundStyle(
            Palette.blue)
        }
        Text("\(pages.visiblePage?.accountTotal ?? 0) 封邮件").font(.system(size: 11))
          .foregroundStyle(Palette.muted)
      }
      if !compact {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128))], spacing: 8) {
          ForEach(categories, id: \.self) { value in
            Button {
              withAnimation(UIMotion.selection(reduceMotion)) {
                pages.category = pages.category == value ? "" : value
              }
            } label: {
              HStack {
                Image(systemName: value == "账单票据" ? "doc.text" : "folder").foregroundStyle(
                  pages.category == value ? Palette.accent : Palette.muted
                ).font(.system(size: 13))
                Text(value).font(.system(size: 12, weight: .medium))
                  .lineLimit(1).truncationMode(.middle).help(value)
                Spacer()
                Text(
                  "\(pages.visiblePage?.categoryCounts.first { $0.name == value }?.count ?? 0)"
                )
                .font(
                  .system(size: 12, weight: .medium)
                ).monospacedDigit()
              }.padding(.horizontal, 12).frame(height: 42).frame(maxWidth: .infinity)
                .contentShape(
                  Rectangle()
                )
                .background(
                  pages.category == value ? Palette.accentSoft : .white,
                  in: RoundedRectangle(cornerRadius: 8)
                )
            }.buttonStyle(ControlFeedback(selected: pages.category == value))
              .controlFocus()
              .accessibilityAddTraits(pages.category == value ? .isSelected : [])
          }
        }
      }
    }
  }
  private func approveButton(_ job: AgentJob) -> some View {
    WorkflowAction(title: "确认应用分类", icon: "checkmark", color: Palette.blue) {
      store.action("approve") {
        try await BackendService.shared.perform("/jobs/\(job.id)/approve")
      }
    }.disabled(running || store.busy.contains("approve"))
  }
  @ViewBuilder private func reviewSection(_ job: AgentJob, compact: Bool) -> some View {
    if compact {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("\(job.result?.items?.count ?? 0) 条分类建议").font(UIType.section)
          Spacer()
          approveButton(job)
        }
        reviewList(job)
      }.padding(12).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
    } else {
      SectionCard(title: running ? "已完成的建议" : "确认分类建议", icon: "checklist") {
        HStack {
          Text("\(job.result?.items?.count ?? 0) 封邮件 · 仅修改本机标签").font(.system(size: 11))
            .foregroundStyle(Palette.muted)
          Spacer()
          approveButton(job)
        }
        reviewList(job)
      }
    }
  }
  private func reviewList(_ job: AgentJob) -> some View {
    OrganizationReviewList(
      jobId: job.id, items: job.result?.items ?? [], output: streamingOutput,
      offset: $reviewOffset,
      message: { id in store.messages.first { $0.id == id } },
      openMail: { store.openMail($0) })
  }

  private func jobStatus(_ job: AgentJob, compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 6 : 13) {
      HStack {
        if running { ProgressView().controlSize(.small) }
        Label(
          statusTitle(job), systemImage: job.status == "applied" ? "checkmark.circle" : "sparkles"
        )
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(
          job.status == "applied" ? Palette.success : Palette.accent)
        if compact, let progress = job.progress {
          Text("\(progress.completed) / \(progress.total) 封")
            .font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted)
        }
        Spacer()
        if running {
          WorkflowAction(title: "暂停", icon: "pause") { store.pauseOrganization(job) }
            .disabled(store.busy.contains("organize-control"))
        } else if ["partial", "paused", "failed"].contains(job.status), job.progress != nil {
          WorkflowAction(title: "继续未完成邮件", icon: "arrow.clockwise", color: Palette.blue) {
            store.organize(retry: job)
          }
          .disabled(store.busy.contains("organize-control"))
        } else if job.status == "applied" {
          WorkflowAction(title: "撤销本次整理", icon: "arrow.uturn.backward") {
            store.action("undo") { try await BackendService.shared.perform("/jobs/\(job.id)/undo") }
          }.disabled(store.busy.contains("undo"))
        }
      }
      if let progress = job.progress {
        if !["applied", "undone"].contains(job.status) {
          ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
            .tint(
              Palette.accent
            )
            .animation(UIMotion.selection(reduceMotion), value: progress.completed)
        }
        if !compact {
          HStack {
            Text("已分析 \(progress.completed) / \(progress.total) 封")
              .contentTransition(reduceMotion ? .identity : .numericText())
            Spacer()
            Text(running ? "正在分析第 \(max(1, progress.batch)) 批" : "建议保存在本机")
          }.font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
        }
      }
      if let error = job.error, !error.isEmpty {
        Text(
          job.progress == nil && job.status == "failed"
            ? "上次连接中断或超时，可在上方重新开始分批整理。" : error
        )
        .font(.system(size: 11)).foregroundStyle(Palette.amber).textSelection(.enabled)
      }
      if running && !compact {
        Text("完成后在这里确认分类；暂停不会清空已完成的建议。").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
    }.padding(compact ? 10 : 18).background(
      Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10))
  }
  private func statusTitle(_ job: AgentJob) -> String {
    switch job.status {
    case "running": return "正在整理收件箱"
    case "needsApproval": return "整理完成，等待确认"
    case "partial": return "部分完成，已有建议可先确认"
    case "paused": return "整理已暂停"
    case "applied": return "分类已应用"
    case "undone": return "已撤销本次整理"
    default: return job.progress == nil ? "上次整理未完成" : "本次整理未完成"
    }
  }
}
