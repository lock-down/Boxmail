import BoxmailCore
import SwiftUI

struct AttachmentsView: View {
  @Bindable var store: MailStore
  @ViewState private var pages: AttachmentPageStore
  init(store: MailStore) {
    self.store = store
    _pages = ViewState(
      initialValue: store.attachmentWorkspace())
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      WorkspaceHeader(title: "附件中心", subtitle: "集中查找、预览和比较附件") {
        if let page = pages.visiblePage {
          Text("\(page.analyzedTotal) 个已有理解结果").font(UIType.caption).foregroundStyle(Palette.muted)
            .monospacedDigit()
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) {
          searchField.frame(minWidth: 210, idealWidth: 300, maxWidth: 360)
          Spacer(minLength: 0)
          typeFilters
        }
        VStack(alignment: .leading, spacing: 12) {
          searchField
          typeFilters
        }
      }
      HStack(spacing: 8) {
        Text(
          pages.showsPreviousPage
            ? (pages.loading ? "正在更新附件…" : "保留上次加载的附件")
            : pages.visiblePage.map { "\($0.total) 个附件" } ?? "正在加载附件…"
        ).font(UIType.caption).monospacedDigit().foregroundStyle(Palette.muted)
        if pages.loading { CossSpinner(size: 12) }
        Spacer(minLength: 8)
        comparisonControls
        if !pages.sourceMessageId.isEmpty {
          Text("· 已限定来源邮件").font(UIType.caption).foregroundStyle(Palette.muted)
          ActionButton(title: "清除来源", size: .compact) { pages.sourceMessageId = "" }
        }
      }
      if let error = pages.error {
        PageStoreErrorRow(
          error: error, canRestore: pages.canRestoreLoadedPage,
          restore: { pages.restoreLoadedPage() },
          retry: { Task { await pages.load(revision: store.workspaceListRevision, force: true) } })
      }
      if let page = pages.visiblePage, !page.items.isEmpty {
        AttachmentListView(
          items: page.items, sortOrder: $pages.sortOrder,
          preview: {
            pages.selectedAttachmentId = $0.id
            store.previewFile($0)
          },
          scrollPosition: pages.scrollPosition, externalSelection: $pages.selectedAttachmentId,
          onlySource: { pages.sourceMessageId = $0 },
          selectComparison: { id in
            if store.assistant.attachmentIds.contains(id) {
              store.assistant.attachmentIds.remove(id)
            } else {
              store.assistant.attachmentIds.insert(id)
            }
          },
          comparisonSelection: store.assistant.attachmentIds,
          openMail: { id in
            store.openSourceMessage(id)
          }, download: { store.download($0) }
        ) {
          ListPagination(
            offset: page.offset, count: page.items.count, total: page.total,
            limit: page.limit, unit: "个", subject: "附件",
            loading: pages.loading || pages.showsPreviousPage,
            previous: { pages.previous() }, next: { pages.next() })
        }
        .stalePage(pages.showsPreviousPage, id: pages.loadedRequest)
      } else if pages.visiblePage != nil, !pages.loading, pages.error == nil {
        emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.workspacePage().background(Palette.paper)
      .onChange(of: pages.request) { _, _ in pages.scrollPosition.origin = .zero }
      .onChange(of: store.accountId) { _, _ in pages = store.attachmentWorkspace() }
      .task(id: RefreshKey(request: pages.request, revision: store.workspaceListRevision)) {
        await pages.load(revision: store.workspaceListRevision)
      }
  }
  @ViewBuilder private var comparisonControls: some View {
    if !store.assistant.attachmentIds.isEmpty {
      HStack(spacing: 8) {
        Text("已选 \(store.assistant.attachmentIds.count) 个").font(UIType.caption).foregroundStyle(
          Palette.muted
        ).monospacedDigit()
        ActionButton(title: "清除", size: .compact) { store.assistant.attachmentIds.removeAll() }
        ActionButton(title: "比较附件", icon: .fileCopyLine, color: Palette.accent, emphasis: .tinted) {
          store.assistant.beginAttachmentComparison()
        }.disabled(store.assistant.attachmentIds.count < 2 || store.assistant.busy)
      }
    }
  }
  private var emptyState: some View {
    let hasFiles = (pages.visiblePage?.accountTotal ?? 0) > 0
    return EmptyState(
      title: store.currentAccount == nil ? "先添加邮箱" : hasFiles ? "没有匹配的附件" : "还没有附件",
      subtitle: store.currentAccount == nil
        ? "添加邮箱并同步后，可以在这里查找和预览附件。"
        : hasFiles
          ? "当前搜索或文件类型没有结果，可以清除条件后查看全部附件。"
          : "同步邮箱后，附件会集中显示在这里。", icon: .attachment2,
      actionTitle: store.currentAccount == nil
        ? "添加邮箱"
        : hasFiles
          ? "清除筛选，查看全部"
          : store.currentAccount?.isDemo == true ? nil : "同步邮箱",
      actionDisabled: !hasFiles && store.busy.contains("sync")
    ) {
      if store.currentAccount == nil {
        store.settingsTab = "账号"
        store.showSettings = true
      } else if hasFiles {
        pages.query = ""
        pages.type = "全部"
      } else {
        Task { await store.syncAll() }
      }
    }
  }
  private var searchField: some View {
    SearchField(placeholder: "在当前账户的附件中搜索", text: $pages.query)
  }
  private var typeFilters: some View {
    FilterBar(
      values: ["全部", "PDF", "Word", "表格", "PPT", "TXT", "图片", "ZIP"],
      selection: $pages.type, compact: true)
  }
}
