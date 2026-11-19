import BoxmailCore
import SwiftUI

struct ContentView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var activity = false
  @ViewState<Bool> private var searchFilters = false
  @ViewState<Bool> private var showingNavigation = false
  @ViewState<Bool> private var usedStartupPage = false
  @ViewState private var windowZoom = WindowZoomController()
  @AppStorage("BoxmailSummaryPreview") private var summaryPreview = false
  @AppStorage("BoxmailGroupMailBySender") private var groupMailBySender = true
  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < MainWindowLayout.sidebarThreshold
      let workspaceWidth = geometry.size.width - (compact ? 0 : UILayout.sidebar + 1)
      let inlineAssistant = workspaceWidth >= MainWindowLayout.inlineAssistantWidth
      let showingAssistant = store.ready && store.assistant.isPresented
      HStack(spacing: 0) {
        if !compact {
          SidebarView(store: store).frame(width: UILayout.sidebar)
          Divider().overlay(Palette.softBorder)
        }
        VStack(spacing: 0) {
          header(compact: compact, height: geometry.size.height)
          Divider().overlay(Palette.softBorder)
          if !store.search.isEmpty || store.mailSource != nil { sourceContext }
          workspace
            .padding(.trailing, showingAssistant && inlineAssistant ? UILayout.assistant + 1 : 0)
            .overlay(alignment: .trailing) {
              if showingAssistant {
                HStack(spacing: 0) {
                  Divider().overlay(Palette.softBorder)
                  AssistantWorkspaceView(store: store, workspace: store.assistant) { id in
                    if !inlineAssistant { store.assistant.isPresented = false }
                    store.openSourceMessage(id)
                  }.frame(width: UILayout.assistant)
                }
                .shadow(color: .black.opacity(inlineAssistant ? 0 : 0.12), radius: 12, x: -4)
              }
            }
          if store.mailChange != nil || store.mailActionError != nil { mailActionNotice }
        }
      }
      .sheet(isPresented: $store.showSettings) {
        SettingsView(store: store).borderlessScrollers()
          .workspaceSheet(.settings)
      }
      .sheet(item: $store.composer) { draft in
        ComposerView(store: store, initial: draft).borderlessScrollers()
          .workspaceSheet(.composer)
      }
      .sheet(item: $store.previewAttachment, onDismiss: { store.attachmentPreviewIds = []; store.attachmentPreviewIndex = 0; store.trimAttachmentCache(keeping: Array(store.retainedAttachmentIds)) }) { attachment in
        AttachmentPreviewView(store: store, attachmentId: attachment.id).borderlessScrollers()
          .workspaceSheet(.attachment)
      }
      .sheet(isPresented: $activity) { ActivityView(store: store).borderlessScrollers() }
      .environment(\.workspaceViewport, geometry.size)
    }.foregroundStyle(Palette.ink).tint(Palette.blue).background(Palette.canvas).ignoresSafeArea(
      .container, edges: .top
    )
    .borderlessScrollers()
    .onAppear { store.changeSenderGrouping(groupMailBySender); store.showSummaryPreview = summaryPreview }
    .onChange(of: store.showSummaryPreview) { _, value in summaryPreview = value }
    .task(id: store.ready) {
      guard store.ready else { return }
      await store.loadSavedSearches()
      while !Task.isCancelled {
        await store.observeWorkspaceChanges()
        await store.notifications.poll(store: store)
        if store.destination == .outbox { await store.sendQueue.load() }
        if store.destination == .followUps { await store.followUps.load() }
        if store.destination == .rules { await store.rules.load() }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
      }
    }
    .onChange(of: store.groupMailBySender) { _, value in groupMailBySender = value }
    .onChange(of: store.destination) { _, _ in showingNavigation = false }
    .onChange(of: store.accountId) { _, _ in showingNavigation = false }
    .onChange(of: store.composer?.id) { _, _ in showingNavigation = false }
    .onChange(of: store.showSettings) { _, showing in if showing { showingNavigation = false } }
    .task(id: store.ready ? store.mailQueryKey : "") {
      guard store.ready else { return }
      if store.restoredMailQueryKey == store.mailQueryKey { store.restoredMailQueryKey = nil; return }
      guard store.isMailWorkspace else { return }
      if !usedStartupPage {
        usedStartupPage = true
        // Startup already awaited the first page. Later navigation still needs
        // a fresh query even when returning to a previously loaded folder.
        if store.pageKey == store.mailQueryKey { return }
      }
      do {
        try await Task.sleep(for: .milliseconds(180))
        try Task.checkCancellation()
      } catch { return }
      await store.loadMessages(reset: true, preserveSelection: store.pageKey == store.mailQueryKey)
    }
    .task(id: store.selectedMessageId) {
      guard store.ready else { return }
      await store.loadSelectedMessage()
    }
    .storeAlert(
      "操作未完成", text: { store.error }, isPresented: {
        store.error != nil && !store.showSettings && store.composer == nil
          && store.previewAttachment == nil
      }, dismiss: { store.error = nil })
    .storeAlert(
      "Boxmail", text: { store.notice }, isPresented: { store.notice != nil },
      dismiss: { store.notice = nil })
  }
  @ViewBuilder private var workspace: some View {
    if !store.ready {
      startupContent
    } else {
      switch store.destination {
      case .followUps, .summary: searchableWorkspace { MailWorkbenchView(store: store) }
      case .rules: RuleWorkspaceView(store: store, workspace: store.rules)
      case .outbox: SendQueueView(store: store, workspace: store.sendQueue)
      case .attachments: searchableWorkspace { AttachmentsView(store: store) }
      case .organize: searchableWorkspace {
        OrganizeView(store: store).id("\(store.accountId)-\(store.restoreRevision)")
      }
      case .drafts: searchableWorkspace { DraftsView(store: store) }
      default: mailSplit
      }
    }
  }
  private func searchableWorkspace<Content: View>(@ViewBuilder content: () -> Content) -> some View
  {
    ZStack {
      content().opacity(store.search.isEmpty ? 1 : 0)
        .allowsHitTesting(store.search.isEmpty).accessibilityHidden(!store.search.isEmpty)
      if !store.search.isEmpty { mailSplit }
    }
  }
  private var startupContent: some View {
    VStack(spacing: 16) {
      if let error = store.startupError {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .font(.system(size: 30, weight: .light)).foregroundStyle(Palette.muted)
        Text("本机服务暂时无法启动").font(UIType.heading)
        Text(error).font(UIType.caption).foregroundStyle(Palette.muted)
          .multilineTextAlignment(.center).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 480)
        HStack(spacing: 10) {
          ActionButton(title: "打开数据设置", icon: "slider.horizontal.3") {
            store.settingsTab = "高级"
            store.showSettings = true
          }
          ActionButton(title: "重试", icon: "arrow.clockwise", color: Palette.accent) {
            Task { await store.load() }
          }
        }
      } else {
        ProgressView()
        Text(BackendService.shared.pendingDataDirectory == nil
          ? "正在启动本机邮件服务…" : "正在迁移本机数据，请保持磁盘连接…")
          .font(UIType.caption).foregroundStyle(Palette.muted)
      }
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  private var mailSplit: some View {
    HSplitView {
      MailListView(store: store).frame(minWidth: UILayout.mailListMinimum, idealWidth: 380, maxWidth: 560)
      Group {
        if store.selectedMails.count > 1 {
          VStack(spacing: 14) {
            Image(systemName: "envelope.stack").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.muted)
            Text("已选择 \(store.selectedMails.count) 封邮件").font(UIType.heading)
            Text("使用列表上方的操作批量归档、标记或删除邮件。")
              .font(UIType.caption).foregroundStyle(Palette.muted)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = store.selectedMessage,
          store.filteredMessages.contains(where: { $0.id == message.id })
        {
          if let error = store.detailError {
            VStack(spacing: 14) {
              EmptyState(title: "邮件加载未完成", subtitle: error, icon: "envelope")
              ActionButton(title: "重新加载", icon: "arrow.clockwise") {
                Task { await store.loadSelectedMessage() }
              }
            }
          } else if message.bodyLoaded == false {
            ProgressView("正在加载邮件正文…").frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if message.draftId != nil {
            DraftSearchDetailView(store: store, message: message)
          } else {
            MailDetailView(store: store, message: message)
          }
        } else if !store.search.isEmpty && store.filteredMessages.isEmpty {
          EmptyState(
            title: "暂无可预览内容", subtitle: "更换关键词或清除搜索，继续浏览邮件。", icon: "magnifyingglass")
        } else {
          EmptyState(
            title: store.filteredMessages.isEmpty ? "这里还没有邮件" : "选择一封邮件",
            subtitle: store.currentAccount?.isDemo == true
              ? "你正在浏览演示数据。添加邮箱后可同步真实邮件。" : "同步邮箱，或从列表中选择邮件查看内容。")
        }
      }.frame(minWidth: UILayout.readingMinimum, maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
  }
  private func header(compact: Bool, height: CGFloat) -> some View {
    HStack(spacing: 10) {
      if compact {
        IconButton(icon: "sidebar.left", help: "显示邮箱与账户") { showingNavigation.toggle() }
          .popover(isPresented: $showingNavigation, arrowEdge: .bottom) {
            SidebarView(store: store).frame(
              width: UILayout.sidebar, height: min(640, max(440, height - 64)))
          }
        IconButton(icon: "square.and.pencil", help: "写邮件（Command-N）") { store.newDraft() }
      }
      WindowTitlebarRegion(zoom: windowZoom)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).layoutPriority(-1)
      HStack(spacing: 4) {
        SearchField(
          placeholder: "搜索邮件（含附件内容）", text: $store.search, focusRequest: store.searchFocusRequest)
        IconButton(icon: "line.3.horizontal.decrease", help: "组合条件搜索") { searchFilters = true }
          .popover(isPresented: $searchFilters, arrowEdge: .bottom) { SearchFiltersView(store: store) }
      }.frame(minWidth: 180, idealWidth: 420, maxWidth: 520)
      WindowTitlebarRegion(zoom: windowZoom)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).layoutPriority(-1)
      HStack(spacing: 6) {
        SelectionButton(title: "邮件助手", icon: "text.bubble", selected: store.assistant.isPresented, size: .compact) {
          store.assistant.isPresented.toggle()
        }.disabled(!store.ready).keyboardShortcut("j", modifiers: [.command, .shift])
          .help("展开或收起右侧邮件助手（Command-Shift-J）")
        if store.busy.contains("sync") {
          ProgressView().controlSize(.small).frame(width: 18).accessibilityLabel(store.syncProgressText)
          IconButton(icon: "stop.fill", help: "停止本次同步，保留已下载邮件") {
            Task { await store.cancelSync() }
          }.disabled(store.syncCancelInFlight)
        } else {
          IconButton(icon: "arrow.triangle.2.circlepath", help: "同步所有账户") {
            Task { await store.syncAll() }
          }
        }
        IconButton(icon: "bell", help: "活动记录") { activity = true }
        IconButton(icon: "gearshape", help: "设置") { store.showSettings = true }
      }.padding(.trailing, 14)
    }.padding(.leading, compact ? 80 : 16).frame(height: 48).background(Palette.chrome)
  }
  private var sourceContext: some View {
    HStack(spacing: 12) {
      ActionButton(title: store.mailSource?.returnTitle ?? "返回\(store.destination.title)", icon: "chevron.left") {
        if store.mailSource != nil { store.returnToMailSource() }
        else { store.search = "" }
      }
      if let source = store.mailSource {
        Text(store.accounts.first { $0.id == source.accountId }?.email ?? "来源账户")
          .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1)
      } else {
        Text("邮件搜索").font(UIType.caption).foregroundStyle(Palette.ink)
        Text("仅搜索已下载的邮件与附件内容")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
      Spacer(minLength: 0)
    }.padding(.horizontal, 12).frame(height: 36).background(Palette.chrome)
      .overlay(alignment: .bottom) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
  }
  private var mailActionNotice: some View {
    HStack(spacing: 10) {
      Text(store.mailActionError ?? store.mailChange?.title ?? "")
        .font(UIType.caption).foregroundStyle(store.mailActionError == nil ? Palette.muted : Palette.amber)
        .lineLimit(2).textSelection(.enabled)
      Spacer(minLength: 8)
      if store.mailChange?.undo.isEmpty == false {
        ActionButton(title: "撤销", icon: "arrow.uturn.backward", color: Palette.accent) { store.undoMailChange() }
          .disabled(store.mailActionInProgress).help("撤销最近一次邮件操作（Command-Z）")
      }
      IconButton(icon: "xmark", help: "关闭邮件操作提示", size: 24) {
        store.mailChange = nil; store.mailActionError = nil
        store.mailUndoManager?.removeAllActions(withTarget: store)
      }.disabled(store.mailActionInProgress)
    }.padding(.horizontal, 16).padding(.vertical, 4).background(Palette.canvas)
  }
}
