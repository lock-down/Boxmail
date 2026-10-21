import BoxmailCore
import SwiftUI

struct ContentView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var activity = false
  @ViewState<Bool> private var searchFilters = false
  var body: some View {
    HStack(spacing: 0) {
      SidebarView(store: store).frame(width: UILayout.sidebar)
      Divider().overlay(Palette.softBorder)
      VStack(spacing: 0) {
        header
        Divider().overlay(Palette.softBorder)
        workspace
      }
    }.foregroundStyle(Palette.ink).tint(Palette.blue).background(Palette.canvas).ignoresSafeArea(
      .container, edges: .top
    )
    .borderlessScrollers()
    .sheet(isPresented: $store.showSettings) { SettingsView(store: store).borderlessScrollers() }
    .sheet(item: $store.composer) { draft in
      ComposerView(store: store, initial: draft).borderlessScrollers()
    }
    .sheet(item: $store.previewAttachment) { attachment in
      AttachmentPreviewView(store: store, attachmentId: attachment.id).borderlessScrollers()
    }
    .sheet(isPresented: $activity) { ActivityView(store: store).borderlessScrollers() }
    .task(id: store.ready ? store.mailQueryKey : "") {
      guard store.ready else { return }
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
    } else if !store.search.isEmpty {
      mailSplit
    } else {
      switch store.destination {
      case .attachments: AttachmentsView(store: store)
      case .organize: OrganizeView(store: store)
      case .summary: SummaryOverviewView(store: store)
      case .drafts: DraftsView(store: store)
      default: mailSplit
      }
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
      MailListView(store: store).frame(minWidth: 294, idealWidth: 332, maxWidth: 380)
      Group {
        if let message = store.selectedMessage,
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
      }.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }
  }
  private var header: some View {
    HStack(spacing: 16) {
      Spacer(minLength: 0)
      HStack(spacing: 4) {
        SearchField(placeholder: "搜索邮件、附件或输入条件", text: $store.search)
        IconButton(icon: "line.3.horizontal.decrease", help: "组合条件搜索") { searchFilters = true }
          .popover(isPresented: $searchFilters, arrowEdge: .bottom) { SearchFiltersView(store: store) }
      }.frame(minWidth: 220, idealWidth: 420, maxWidth: 520)
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        Button {
          store.settingsTab = "AI 助手"
          store.showSettings = true
        } label: {
          HStack(spacing: 6) {
            Circle().fill(store.settings.ai.enabled ? Palette.success : Palette.muted)
              .frame(width: 5, height: 5)
            Text("AI 助手").font(.system(size: 11, weight: .medium))
          }.foregroundStyle(Palette.muted).padding(.horizontal, 9).frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(ControlFeedback()).controlFocus()
          .accessibilityLabel(store.settings.ai.enabled ? "AI 助手已开启" : "AI 助手已关闭")
          .help("打开 AI 设置")
        if store.busy.contains("sync") {
          ProgressView().controlSize(.small).frame(width: 26)
        } else {
          IconButton(icon: "arrow.triangle.2.circlepath", help: "同步所有账户") {
            Task { await store.syncAll() }
          }
        }
        IconButton(icon: "bell", help: "活动记录") { activity = true }
        IconButton(icon: "gearshape", help: "设置") { store.showSettings = true }
      }.padding(.trailing, 14)
    }.padding(.leading, 16).frame(height: 54).background(Palette.chrome)
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
