import BoxmailCore
import SwiftUI

struct MailListView: View {
  @Bindable var store: MailStore
  @ViewState<MailAccount?> private var trashAccount: MailAccount?
  @ViewState<Bool> private var showingSyncDetails = false
  @Environment(\.undoManager) private var undoManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var emptyingTrash: Bool { store.busy.contains("empty-trash-\(store.accountId)") }
  private var selected: [MailMessage] { store.selectedMails }
  private var emptyFolderHint: String {
    if store.busy.contains("sync") { return "正在同步，请等待服务器返回邮件。" }
    if [.inbox, .sent].contains(store.destination), store.currentAccount?.isDemo == false,
      ["imap.163.com", "imap.126.com", "imap.yeah.net"].contains(store.currentAccount?.imapHost.lowercased() ?? ""),
      store.currentSyncFolder?.total == 0 {
      return "若网页版有历史邮件，请在网易邮箱的 POP3/SMTP/IMAP 设置中选择“收取全部邮件”，保存后重新同步。"
    }
    return "点击顶部同步按钮获取邮件。"
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        HStack(spacing: 6) {
          Text(store.search.isEmpty ? store.destination.title : "搜索结果")
            .font(.system(size: 14, weight: .semibold))
          Text("\(store.pageTotal)").font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted)
          Spacer(minLength: 0)
          MailListDisplayMenu(store: store)
          if store.destination == .trash {
            ActionButton(title: emptyingTrash ? "清空中…" : "清空") { trashAccount = store.currentAccount }
              .disabled(emptyingTrash || store.currentAccount == nil
                || (store.currentAccount?.isDemo == true && store.trashMessages.isEmpty)
                || store.busy.contains("sync") || store.mailActionInProgress)
          }
          IconButton(icon: "checklist", help: "全选当前显示的邮件（Command-A）", size: 28) {
            store.selectAllLoadedMail()
          }.disabled(store.filteredMessages.isEmpty || store.mailActionInProgress)
          IconMenu(icon: "ellipsis", help: "邮件列表操作") {
            Button("全选当前显示的邮件") { store.selectAllLoadedMail() }
            Button("将当前显示的邮件全部标记已读") {
              store.updateMessages(store.filteredMessages.filter { $0.unread }, changes: ["unread": false])
            }
            Divider()
            Button("刷新邮箱") { Task { await store.syncAll() } }
          }.disabled(store.mailActionInProgress)
        }.frame(height: 28)
        if selected.count > 1 {
          MailBatchToolbar(store: store, messages: selected)
        } else {
          FilterBar(values: ["全部", "未读", "有附件", "AI 已总结"], selection: $store.filter, fillsWidth: true)
        }
      }.padding(.horizontal, 12).padding(.vertical, 10)
      Divider().overlay(Palette.softBorder)
      if store.filteredMessages.isEmpty {
        let emptyTrash = store.destination == .trash && store.trashMessages.isEmpty
          && store.search.isEmpty && store.filter == "全部"
        let unfiltered = store.search.isEmpty && store.filter == "全部"
        EmptyState(title: emptyTrash ? "已删除为空" : unfiltered ? "此文件夹暂无邮件" : "没有匹配的邮件",
          subtitle: emptyTrash ? "删除的邮件会显示在这里，可恢复到原文件夹。"
            : unfiltered ? emptyFolderHint : "调整筛选条件，或搜索其他关键词。",
          icon: emptyTrash ? "trash" : "tray")
      } else {
        messageList
      }
      status
    }.background(.white)
      .onAppear { store.mailUndoManager = undoManager; store.reconcileMailSelection() }
      .onChange(of: store.selectedMessageId) { _, _ in store.reconcileMailSelection() }
      .alert("清空已删除邮件？", isPresented: Binding(
        get: { trashAccount != nil }, set: { if !$0 { trashAccount = nil } }), presenting: trashAccount
      ) { account in
        Button("取消", role: .cancel) { trashAccount = nil }
        Button("清空已删除", role: .destructive) {
          store.emptyTrash(account: account); trashAccount = nil
        }
      } message: { account in
        Text("将永久删除 \(account.email) 中的所有已删除邮件及不再使用的附件，包括未显示的邮件。"
          + (account.isDemo ? "此操作无法恢复。" : "此操作会同步到邮箱服务器，无法恢复。"))
      }
  }

  private var messageList: some View {
    let queryKey = store.mailQueryKey
    return ScrollViewReader { reader in
      List(selection: Binding(get: { store.selectedMessageIds }, set: { ids in
        store.setMailSelection(ids, for: queryKey)
      })) {
        if store.usesSenderGroups {
          ForEach(store.senderGroups) { group in
            if let latest = store.pageMessages.first(where: { $0.id == group.latestMessageId }) {
              messageRow(latest, group: group)
              if store.expandedSenderGroups.contains(group.id) {
                ForEach(store.senderChildren(group)) { message in messageRow(message, child: true) }
                MailSenderGroupFooter(store: store, group: group)
                  .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
              }
            }
          }
        } else {
          ForEach(store.filteredMessages) { message in messageRow(message) }
        }
        if store.nextOffset != nil || store.listLoading {
          HStack {
            Spacer()
            if store.listLoading { ProgressView("正在加载…").controlSize(.small) }
            else {
              ActionButton(title: store.usesSenderGroups ? "显示更多发件人" : "显示更多邮件", icon: "chevron.down") {
                Task { await store.loadMessages(reset: false) }
              }
            }
            Spacer()
          }.padding(.vertical, 8).listRowSeparator(.hidden)
        }
      }.listStyle(.plain).scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .focusedValue(\.mailTriage, store)
        .contextMenu(forSelectionType: String.self) { ids in
          MailTriageMenu(store: store, messages: store.filteredMessages.filter { ids.contains($0.id) })
        }
        .onKeyPress(.escape) {
          guard selected.count > 1 else { return .ignored }
          store.clearMailSelection(); return .handled
        }
        .onKeyPress(.rightArrow) {
          store.expandSelectedSenderGroup() ? .handled : .ignored
        }
        .onKeyPress(.leftArrow) {
          store.collapseSelectedSenderGroup() ? .handled : .ignored
        }
        .disabled(store.mailActionInProgress || emptyingTrash)
        .accessibilityLabel("邮件列表")
        .accessibilityHint("上下方向键切换，左右方向键展开或折叠发件人，Shift 连续选择，Command 点击多选，Command-A 全选当前显示的邮件。")
        .id(queryKey)
        .task(id: store.readyMailReveal?.id) {
          guard let request = store.readyMailReveal else { return }
          await Task.yield()
          guard !Task.isCancelled, store.readyMailReveal == request else { return }
          reader.scrollTo(request.messageId, anchor: .center)
          store.finishMailReveal(request)
        }
    }
  }

  private func messageRow(_ message: MailMessage, group: MailSenderGroup? = nil, child: Bool = false) -> some View {
    MailRow(message: message, selected: store.selectedMessageIds.contains(message.id),
      searchAccount: store.search.isEmpty ? nil : store.accounts.first { $0.id == message.accountId }?.email,
      senderGroup: group, isSenderChild: child,
      expanded: group.map { store.expandedSenderGroups.contains($0.id) } ?? false,
      toggleGroup: group.flatMap { value in value.count > 1 ? {
        withAnimation(UIMotion.disclosure(reduceMotion)) { store.toggleSenderGroup(value.id) }
      } : nil })
      .tag(message.id).id(message.id).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
      .listRowBackground(store.selectedMessageIds.contains(message.id) ? Palette.blueSoft : Color.white)
  }

  private var status: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let error = store.listError {
        Text(error).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
        ActionButton(title: "重新加载列表", icon: "arrow.clockwise") {
          Task { await store.loadMessages(reset: true, preserveSelection: true) }
        }
      }
      if let error = store.currentSyncFolder?.lastError ?? store.syncSnapshot?.results.first(where: {
        $0.accountId == store.accountId && $0.status == "failed"
      })?.error {
        Text(error).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
        ActionButton(title: "重试同步", icon: "arrow.clockwise") { Task { await store.syncAll() } }
          .disabled(store.busy.contains("sync"))
      }
      HStack(spacing: 6) {
        if store.busy.contains("sync") {
          ProgressView().controlSize(.mini)
          Text(store.syncProgressText).lineLimit(1)
        } else if !store.search.isEmpty {
          Text("仅搜索本机已缓存邮件")
        } else if store.currentAccount?.isDemo == true {
          Text("演示邮箱")
        } else if let time = store.currentAccount?.lastSync {
          Text("上次同步 \(displayTime(time))")
        } else { Text("尚未同步") }
        Spacer(minLength: 0)
        if !store.busy.contains("sync") && (store.currentSyncFolder?.hasMore == true
          || ["failed", "paused"].contains(store.currentSyncFolder?.status ?? "")) {
          Button("继续同步") { Task { await store.syncAll(folder: store.destination.rawValue) } }
            .buttonStyle(.plain).foregroundStyle(Palette.blue).disabled(store.busy.contains("sync"))
        }
        IconButton(icon: "info.circle", help: "查看缓存与同步详情", size: 24) { showingSyncDetails.toggle() }
          .popover(isPresented: $showingSyncDetails) { syncDetails }
      }.font(UIType.small).foregroundStyle(Palette.muted).frame(minHeight: 24)
    }.padding(.horizontal, 12).padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas)
  }

  private var syncDetails: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("缓存与同步").font(UIType.section)
      if store.search.isEmpty && [.inbox, .sent, .trash, .archive].contains(store.destination) {
        Text("本机缓存 \(store.cachedMessageCount(accountId: store.accountId, folder: store.destination.rawValue)) 封")
        if let total = store.currentSyncFolder?.total { Text("上次同步服务器共 \(total) 封") }
      } else { Text("当前列表已加载 \(store.filteredMessages.count) 封") }
      if let time = store.currentAccount?.lastSync { Text("上次同步 \(displayTime(time))") }
      Text("搜索仅覆盖本机已缓存内容；同步期间会自动逐批补齐历史邮件。")
        .foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }.font(UIType.caption).padding(16).frame(width: 280, alignment: .leading)
  }
}

struct MailBatchToolbar: View {
  @Bindable var store: MailStore
  let messages: [MailMessage]
  var body: some View {
    HStack(spacing: 2) {
      Text("已选 \(messages.count) 封").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.blue)
        .lineLimit(1).monospacedDigit()
      Spacer(minLength: 2)
      if messages.allSatisfy({ $0.folder == "trash" || $0.folder == "archive" }) {
        IconButton(icon: "arrow.uturn.backward", help: "恢复所选邮件", size: 28) { store.restoreMessages(messages) }
      } else {
        IconButton(icon: "archivebox", help: "归档所选邮件", size: 28) {
          store.updateMessages(messages.filter { $0.folder != "trash" }, changes: ["folder": "archive"])
        }
      }
      IconMenu(icon: "ellipsis", help: "批量标记与分类") { MailTriageMenu(store: store, messages: messages) }
      IconButton(icon: "trash", help: "将所选邮件移到已删除", size: 28) {
        store.updateMessages(messages.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
      }.disabled(messages.allSatisfy { $0.folder == "trash" })
      IconButton(icon: "xmark", help: "取消选择", size: 28) { store.clearMailSelection() }
    }.frame(height: 32).disabled(store.mailActionInProgress)
  }
}

struct MailTriageMenu: View {
  @Bindable var store: MailStore
  let messages: [MailMessage]
  private var mails: [MailMessage] { messages.filter { $0.draftId == nil } }
  var body: some View {
    if let draft = messages.first, messages.count == 1, let id = draft.draftId {
      Button("继续编辑草稿") { store.editDraft(id) }
    } else if !mails.isEmpty {
      Button("标记已读") { store.updateMessages(mails, changes: ["unread": false]) }
      Button("标记未读") { store.updateMessages(mails, changes: ["unread": true]) }
      Button(mails.allSatisfy(\.starred) ? "取消星标" : "添加星标") {
        store.updateMessages(mails, changes: ["starred": !mails.allSatisfy(\.starred)])
      }
      Menu("分类") {
        ForEach(store.categories) { category in
          Button(category.name) { store.updateMessages(mails, changes: ["category": category.name]) }
        }
      }
      Divider()
      if mails.allSatisfy({ $0.folder == "trash" || $0.folder == "archive" }) {
        Button("恢复到原文件夹") { store.restoreMessages(mails) }
      }
      if mails.contains(where: { $0.folder != "archive" && $0.folder != "trash" }) {
        Button("归档") { store.updateMessages(mails.filter { $0.folder != "trash" }, changes: ["folder": "archive"]) }
      }
      Button("移到已删除") {
        store.updateMessages(mails.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
      }.disabled(mails.allSatisfy { $0.folder == "trash" })
    }
  }
}

struct MailRow: View {
  let message: MailMessage
  var selected = false
  var searchAccount: String? = nil
  var senderGroup: MailSenderGroup? = nil
  var isSenderChild = false
  var expanded = false
  var toggleGroup: (() -> Void)? = nil
  private var unread: Bool { senderGroup.map { $0.unreadCount > 0 } ?? message.unread }
  private var rowLabel: String {
    "\(message.sender)，\(message.subject.isEmpty ? "无主题" : message.subject)，\(accessibilityStatus)"
  }
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if let toggleGroup {
        Button(action: toggleGroup) {
          Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(Palette.muted)
            .frame(width: 20, height: 22).contentShape(Rectangle())
        }.buttonStyle(ControlFeedback(corner: 4)).controlFocus(corner: 4).padding(.top, -3)
          .help("\(expanded ? "折叠" : "展开") \(message.sender) 的 \(senderGroup?.count ?? 0) 封邮件")
          .accessibilityLabel("\(expanded ? "折叠" : "展开") \(message.sender) 的 \(senderGroup?.count ?? 0) 封邮件")
          .accessibilityValue(expanded ? "已展开" : "已折叠")
      } else if senderGroup != nil {
        Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
      }
      Circle().fill(unread ? Palette.blue : .clear).frame(width: 6, height: 6).padding(.top, 5)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        if !isSenderChild {
          HStack(spacing: 6) {
            Text(message.sender).font(.system(size: 12, weight: unread ? .semibold : .regular)).lineLimit(1)
            if let group = senderGroup, group.count > 1 {
              Text("\(group.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(Palette.muted).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 4))
                .help("共 \(group.count) 封，\(group.unreadCount) 封未读")
            }
            Spacer(minLength: 0)
            Text(displayTime(message.date)).font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted).fixedSize()
          }
        }
        HStack(spacing: 6) {
          Text(message.subject.isEmpty ? "（无主题）" : message.subject)
            .font(.system(size: 13, weight: message.unread ? .semibold : .medium)).lineLimit(1)
          Spacer(minLength: 0)
          if isSenderChild {
            Text(displayTime(message.date)).font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted).fixedSize()
          }
          if message.starred { Image(systemName: "star.fill").foregroundStyle(Palette.amber) }
          if message.summary != nil {
            Image(systemName: "sparkles").foregroundStyle(Palette.blue).help("已有 AI 总结")
          }
          if !message.attachmentIds.isEmpty {
            Image(systemName: "paperclip").foregroundStyle(Palette.muted).help("\(message.attachmentIds.count) 个附件")
          }
        }.font(.system(size: 11))
        HStack(spacing: 8) {
          Text(message.searchSnippet ?? message.preview).font(UIType.caption).foregroundStyle(Palette.muted)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
          if message.category != "未分类" {
            Text(message.category).font(UIType.small).foregroundStyle(Palette.muted)
              .lineLimit(1).frame(maxWidth: 72, alignment: .trailing)
          }
        }
        if let searchAccount {
          Text("\(searchAccount) · \(MailDestination(rawValue: message.folder)?.title ?? "垃圾邮件")")
            .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
        }
      }.accessibilityElement(children: .ignore).accessibilityLabel(rowLabel)
        .accessibilityHint(message.preview)
    }.padding(.leading, isSenderChild ? 40 : 12).padding(.trailing, 12).padding(.vertical, isSenderChild ? 9 : 11)
      .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.ink)
      .background(selected ? Palette.blueSoft : .white)
      .overlay(alignment: .leading) { if selected { Rectangle().fill(Palette.blue).frame(width: 1) } }
      .overlay(alignment: .bottom) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
      .accessibilityElement(children: .contain)
  }
  private var accessibilityStatus: String {
    var parts = [message.unread ? "未读" : "已读", displayTime(message.date)]
    if !message.attachmentIds.isEmpty { parts.append("\(message.attachmentIds.count) 个附件") }
    if message.starred { parts.append("已加星标") }
    if message.summary != nil { parts.append("已有 AI 总结") }
    if message.category != "未分类" { parts.append(message.category) }
    if let searchAccount { parts.append(searchAccount) }
    if let group = senderGroup, group.count > 1 {
      parts.append("同一发件人共 \(group.count) 封，\(group.unreadCount) 封未读，\(expanded ? "已展开" : "已折叠")")
    }
    return parts.joined(separator: "，")
  }
}
