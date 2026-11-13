import BoxmailCore
import SwiftUI

struct AttachmentsView: View {
  @Bindable var store: MailStore
  @ViewState private var pages: AttachmentPageStore
  init(store: MailStore) {
    self.store = store
    _pages = ViewState(
      initialValue: AttachmentPageStore(backend: store.backend, accountId: store.accountId))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        PageHeading(title: "附件中心", subtitle: "查找、预览和下载附件，在原邮件中使用 AI 理解")
        Spacer()
        if let page = pages.visiblePage {
          Tag(text: "\(page.analyzedTotal) 个 AI 已解析", ai: true)
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
      HStack {
        Text(
          pages.showsPreviousPage
            ? (pages.loading ? "正在更新附件…" : "保留上次加载的附件")
            : pages.visiblePage.map { "\($0.total) 个附件" } ?? "正在加载附件…"
        )
        .font(.system(size: 12, weight: .medium))
        if pages.loading { ProgressView().controlSize(.mini) }
        Spacer()
        Text("支持文档、图片和 ZIP 资料包理解").font(UIType.small).foregroundStyle(Palette.muted)
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
          preview: { store.previewAttachment = $0 },
          openMail: { id in
            if let message = store.messages.first(where: { $0.id == id }) {
              store.openMail(message, tab: .attachment)
            }
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
    }.workspacePage().background(Palette.canvas)
      .onChange(of: store.accountId) { _, id in pages.accountId = id }
      .task(id: RefreshKey(request: pages.request, revision: store.workspaceListRevision)) {
        await pages.load(revision: store.workspaceListRevision)
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
          : "同步邮箱后，附件会集中显示在这里。", icon: "paperclip",
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
