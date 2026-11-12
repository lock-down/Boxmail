import BoxmailCore
import SwiftUI

struct ContentView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var activity = false
  @ViewState<Bool> private var searchFilters = false
  @ViewState<Bool> private var showingNavigation = false
  @ViewState<Bool> private var usedStartupPage = false
  @ViewState private var windowZoom = WindowZoomController()
  @AppStorage("BoxmailGroupMailBySender") private var groupMailBySender = true
  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        if geometry.size.width >= 1080 {
          SidebarView(store: store).frame(width: UILayout.sidebar)
          Divider().overlay(Palette.softBorder)
        }
        VStack(spacing: 0) {
          header(compact: geometry.size.width < 1080, height: geometry.size.height)
          Divider().overlay(Palette.softBorder)
          if !store.search.isEmpty { searchContext }
          workspace
          if store.mailChange != nil || store.mailActionError != nil { mailActionNotice }
        }
      }
      .sheet(isPresented: $store.showSettings) {
        SettingsView(store: store).borderlessScrollers()
          .frame(
            width: min(1000, max(700, geometry.size.width - 24)),
            height: min(750, max(500, geometry.size.height - 40)))
      }
      .sheet(item: $store.composer) { draft in
        ComposerView(store: store, initial: draft).borderlessScrollers()
          .frame(
            width: min(1080, max(680, geometry.size.width - 24)),
            height: min(720, max(500, geometry.size.height - 40)))
      }
    }.foregroundStyle(Palette.ink).tint(Palette.blue).background(Palette.canvas).ignoresSafeArea(
      .container, edges: .top
    )
    .borderlessScrollers()
    .onAppear { store.changeSenderGrouping(groupMailBySender) }
    .onChange(of: store.groupMailBySender) { _, value in groupMailBySender = value }
    .onChange(of: store.destination) { _, _ in showingNavigation = false }
    .onChange(of: store.accountId) { _, _ in showingNavigation = false }
    .onChange(of: store.composer?.id) { _, _ in showingNavigation = false }
    .onChange(of: store.showSettings) { _, showing in if showing { showingNavigation = false } }
    .sheet(item: $store.previewAttachment) { attachment in
      AttachmentPreviewView(store: store, attachmentId: attachment.id).borderlessScrollers()
    }
    .sheet(isPresented: $activity) { ActivityView(store: store).borderlessScrollers() }
    .task(id: store.ready ? store.mailQueryKey : "") {
      guard store.ready else { return }
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
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: {
          store.error != nil && !store.showSettings && store.composer == nil
            && store.previewAttachment == nil
        }, set: { if !$0 { store.error = nil } })
    ) {
      Button("确定") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .alert(
      "Boxmail",
      isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("确定") { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
  }
  @ViewBuilder private var workspace: some View {
    if !store.ready {
      startupContent
    } else {
      switch store.destination {
      case .attachments: searchableWorkspace { AttachmentsView(store: store) }
      case .organize: searchableWorkspace { OrganizeView(store: store) }
      case .summary: searchableWorkspace { SummaryOverviewView(store: store) }
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
          ActionButton(title: "重试", icon: "arrow.clockwise", kind: .primary) {
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
      MailListView(store: store).frame(minWidth: 294, idealWidth: 380, maxWidth: 560)
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
      }.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity).background(.white)
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
        Button {
          store.settingsTab = "AI 助手"
          store.showSettings = true
        } label: {
          HStack(spacing: 6) {
            Circle().fill(store.settings.ai.enabled ? Palette.success : Palette.muted)
              .frame(width: 5, height: 5)
            if !compact {
              Text(store.settings.ai.enabled ? "AI 已启用" : "AI 已关闭").font(
                .system(size: 11, weight: .medium))
            } else {
              Text("AI").font(UIType.small)
            }
          }.foregroundStyle(Palette.muted).padding(.horizontal, 9).frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(ControlFeedback()).controlFocus()
          .accessibilityLabel(store.settings.ai.enabled ? "AI 助手已开启" : "AI 助手已关闭")
          .help("打开 AI 设置")
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
  private var searchContext: some View {
    HStack(spacing: 12) {
      ActionButton(title: "返回\(store.destination.title)", icon: "chevron.left") {
        store.search = ""
      }
      Text("邮件搜索").font(UIType.caption).foregroundStyle(Palette.ink)
      Text("仅搜索已下载的邮件与附件内容")
        .font(UIType.small).foregroundStyle(Palette.muted)
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
        ActionButton(title: "撤销", icon: "arrow.uturn.backward", kind: .primary) { store.undoMailChange() }
          .disabled(store.mailActionInProgress).help("撤销最近一次邮件操作（Command-Z）")
      }
      IconButton(icon: "xmark", help: "关闭邮件操作提示", size: 24) {
        store.mailChange = nil; store.mailActionError = nil
        store.mailUndoManager?.removeAllActions(withTarget: store)
      }.disabled(store.mailActionInProgress)
    }.padding(.horizontal, 16).padding(.vertical, 4).background(Palette.canvas)
  }
}

struct ActivityView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        PageHeading(title: "活动记录", subtitle: "查看同步、AI 任务与发送状态")
        Spacer()
        IconButton(icon: "xmark", help: "关闭") { dismiss() }
      }
      OverlayScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(store.events) { event in
            HStack {
              Image(systemName: activityIcon(event.type)).foregroundStyle(
                event.type == "send-warning" ? Palette.amber : Palette.muted
              ).frame(width: 28)
              VStack(alignment: .leading, spacing: 4) {
                Text(activityTitle(event.detail)).font(.system(size: 12)).textSelection(.enabled)
                Text(displayTime(event.time)).font(.system(size: 11)).monospacedDigit()
                  .foregroundStyle(Palette.muted)
              }
              Spacer()
            }.padding(.vertical, 15)
            Divider().overlay(Palette.softBorder)
          }
          if store.events.isEmpty {
            EmptyState(title: "还没有活动记录", subtitle: "同步、AI 任务和发送状态会显示在这里。", icon: "clock").frame(
              height: 260)
          }
        }
      }
    }.padding(24).frame(width: 640, height: 480)
  }
  private func activityTitle(_ detail: String) -> String {
    let parts = detail.split(maxSplits: 1, whereSeparator: { $0 == ":" || $0 == "：" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let tasks = [
      "summary": "邮件总结", "reply": "AI 回复", "compose": "AI 写信", "classify": "邮件整理",
      "attachment": "附件理解", "translate": "邮件翻译",
    ]
    let statuses = [
      "completed": "已完成", "needsApproval": "待确认", "failed": "未完成", "running": "正在处理",
      "paused": "已暂停", "partial": "部分完成", "applied": "已应用", "undone": "已撤销",
    ]
    guard parts.count == 2, let task = tasks[parts[0]], let status = statuses[parts[1]] else {
      return detail
    }
    return task + status
  }
  private func activityIcon(_ type: String) -> String {
    switch type {
    case "send": "paperplane"
    case "send-warning": "exclamationmark.triangle"
    case "sync": "arrow.triangle.2.circlepath"
    case "draft": "square.and.pencil"
    case "agent": "sparkles"
    case "organize": "folder"
    default: "clock"
    }
  }
}
