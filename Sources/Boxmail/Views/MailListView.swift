import BoxmailCore
import SwiftUI

private let mailRowHorizontalInset: CGFloat = 12
private let senderDisclosureSize: CGFloat = 24
private let senderBranchPosition = UILayout.listRowInset + mailRowHorizontalInset + senderDisclosureSize / 2
private let senderBranchOffset: CGFloat = 12
private let senderChildInset = senderBranchPosition + senderBranchOffset

struct MailListView: View {
  @Bindable var store: MailStore
  @FocusState private var listFocused: Bool
  @ViewState<MailAccount?> private var trashAccount: MailAccount?
  @ViewState<Bool> private var showingSyncDetails = false
  @ViewState private var compactLabels = false
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
            .font(UIType.heading).accessibilityAddTraits(.isHeader)
          Text("\(store.pageTotal) 封").font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous))
          Spacer(minLength: 0)
          MailListDisplayMenu(store: store)
          SaveMailQueryButton(store: store)
          if store.destination == .trash {
            ActionButton(title: emptyingTrash ? "清空中…" : "清空") { trashAccount = store.currentAccount }
              .disabled(store.unifiedInbox || emptyingTrash || store.currentAccount == nil
                || (store.currentAccount?.isDemo == true && store.trashMessages.isEmpty)
                || store.busy.contains("sync") || store.mailActionInProgress)
          }
          IconMenu(icon: .dots, help: "邮件列表操作") {
            CossMenuItem.command("全选列表", icon: .circleCheck, shortcut: "⌘A",
              enabled: !store.filteredMessages.isEmpty) { store.selectAllLoadedMail() }
            CossMenuItem.command("全标已读", icon: .mailOpened) {
              store.updateMessages(store.filteredMessages.filter { $0.unread }, changes: ["unread": false])
            }
            CossMenuItem.divider
            CossMenuItem.command("同步邮箱", icon: .refresh) { Task { await store.syncAll() } }
          }.disabled(store.mailActionInProgress)
        }.frame(height: 32)
        if selected.count > 1 {
          MailBatchToolbar(store: store, messages: selected)
        } else {
          MailListFilters(store: store)
        }
      }.padding(.horizontal, 12).padding(.vertical, 10)
      CossSeparator()
      if store.filteredMessages.isEmpty {
        let emptyTrash = store.destination == .trash && store.trashMessages.isEmpty
          && store.search.isEmpty && store.filter == "全部"
        let unfiltered = store.search.isEmpty && store.filter == "全部"
        EmptyState(title: emptyTrash ? "已删除为空" : unfiltered ? "此文件夹暂无邮件" : "没有匹配的邮件",
          subtitle: emptyTrash ? "删除的邮件会显示在这里，可恢复到原文件夹。"
            : unfiltered ? emptyFolderHint : "调整筛选条件，或搜索其他关键词。",
          icon: emptyTrash ? .trash : .inbox)
      } else {
        messageList
      }
      status
    }.background(.white)
      .onGeometryChange(for: Bool.self) { $0.size.width < 340 } action: { compactLabels = $0 }
      .onAppear { store.mailUndoManager = undoManager; store.reconcileMailSelection() }
      .onChange(of: store.selectedMessageId) { _, _ in store.reconcileMailSelection() }
      .cossAlert("清空已删除邮件？", isPresented: Binding(
        get: { trashAccount != nil }, set: { if !$0 { trashAccount = nil } }), presenting: trashAccount
      ) { account in
        CossAlertAction("取消", role: .cancel) { trashAccount = nil }
        CossAlertAction("永久清空", role: .destructive) {
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
                  .listRowInsets(EdgeInsets(top: 0, leading: senderChildInset, bottom: 0, trailing: UILayout.listRowInset))
                  .listRowSeparator(.hidden).listRowBackground(Palette.paper)
              }
            }
          }
        } else {
          ForEach(store.filteredMessages) { message in messageRow(message) }
        }
        if store.nextOffset != nil || store.listLoading {
          HStack {
            Spacer()
            if store.listLoading { CossSpinner(label: "正在加载…") }
            else {
              ActionButton(title: "加载更多", icon: .chevronDown,
                help: store.usesSenderGroups ? "加载更多发件人" : "加载更多邮件") {
                Task { await store.loadMessages(reset: false) }
              }
            }
            Spacer()
          }.padding(.vertical, 8).listRowSeparator(.hidden)
        }
      }.cossListStyle()
        .focused($listFocused)
        .onChange(of: store.mailListFocusRequest) { _, _ in listFocused = true }
        .focusedValue(\.mailTriage, store)
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
    MailRow(message: message,
      labels: store.labels(for: message), compactLabels: compactLabels,
      labelMenu: { mailLabelMenu(store: store, messages: [message]) },
      searchAccount: store.search.isEmpty && !(store.unifiedInbox && store.supportsUnifiedScope) ? nil : store.accounts.first { $0.id == message.accountId }?.email,
      senderGroup: group, isSenderChild: child,
      expanded: group.map { store.expandedSenderGroups.contains($0.id) } ?? false,
      toggleGroup: group.flatMap { value in value.count > 1 ? {
        withAnimation(UIMotion.disclosure(reduceMotion)) { store.toggleSenderGroup(value.id) }
      } : nil })
      .cossListRow(selected: store.selectedMessageIds.contains(message.id), showsBorder: false,
        insets: EdgeInsets(top: child ? 0 : 4, leading: child ? senderChildInset : UILayout.listRowInset,
          bottom: child ? 0 : 4, trailing: UILayout.listRowInset))
      .overlay(alignment: .leading) {
        if child {
          Rectangle().fill(Palette.softBorder).frame(width: 1).offset(x: -senderBranchOffset)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .cossContextMenu {
        if !store.mailActionInProgress && !emptyingTrash {
          mailTriageItems(store: store, messages: store.selectedMessageIds.contains(message.id)
            ? store.filteredMessages.filter { store.selectedMessageIds.contains($0.id) } : [message])
        }
      }
      .tag(message.id).id(message.id)
  }

  private var status: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let error = store.listError {
        Text(error).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
        ActionButton(title: "重载列表", icon: .refresh) {
          Task { await store.loadMessages(reset: true, preserveSelection: true) }
        }
      }
      if let error = store.currentSyncFolder?.lastError ?? store.syncSnapshot?.results.first(where: {
        $0.accountId == store.accountId && $0.status == "failed"
      })?.error {
        Text(error).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
        ActionButton(title: "重试同步", icon: .refresh) { Task { await store.syncAll() } }
          .disabled(store.busy.contains("sync"))
      }
      HStack(spacing: 6) {
        if store.busy.contains("sync") {
          CossSpinner(size: 14)
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
          ActionButton(title: "继续同步", color: Palette.accent, size: .compact) {
            Task { await store.syncAll(folder: store.destination.rawValue) }
          }.disabled(store.busy.contains("sync"))
        }
        IconButton(icon: .infoCircle, help: "查看缓存与同步详情", size: 24) { showingSyncDetails.toggle() }
          .cossPopover(isPresented: $showingSyncDetails) { syncDetails }
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
      Text("\(store.pageTotal) 封邮件 · \(store.listUnreadCount) 封未读" )
      if store.usesSenderGroups { Text("\(store.senderGroupTotal) 个发件人组") }
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
    HStack(spacing: 4) {
      Text("已选 \(messages.count) 封").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
        .lineLimit(1).monospacedDigit()
      Spacer(minLength: 4)
      if messages.allSatisfy({ $0.folder == "trash" || $0.folder == "archive" }) {
        IconButton(icon: .arrowBackUp, help: "恢复所选邮件", size: UIControlSize.compact.height) { store.restoreMessages(messages) }
      } else {
        IconButton(icon: .archive, help: "归档所选邮件", size: UIControlSize.compact.height) {
          store.updateMessages(messages.filter { $0.folder != "trash" }, changes: ["folder": "archive"])
        }
      }
      IconMenu(icon: .dots, help: "批量标记与分类", size: UIControlSize.compact.height) {
        mailTriageItems(store: store, messages: messages)
      }
      IconButton(icon: .trash, help: "将所选邮件移到已删除", size: UIControlSize.compact.height) {
        store.updateMessages(messages.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
      }.disabled(messages.allSatisfy { $0.folder == "trash" })
      IconButton(icon: .x, help: "取消选择", size: UIControlSize.compact.height) { store.clearMailSelection() }
    }.frame(height: 32).disabled(store.mailActionInProgress)
  }
}

@MainActor @CossMenuItems
private func mailTriageItems(store: MailStore, messages: [MailMessage]) -> [CossMenuItem] {
  let mails = messages.filter { $0.draftId == nil }
  if let draft = messages.first, messages.count == 1, let id = draft.draftId {
    CossMenuItem.command("继续编辑", icon: .edit) { store.editDraft(id) }
  } else if !mails.isEmpty {
    CossMenuItem.command("标记已读", icon: .mailOpened) { store.updateMessages(mails, changes: ["unread": false]) }
    CossMenuItem.command("标记未读", icon: .mailExclamation) { store.updateMessages(mails, changes: ["unread": true]) }
    CossMenuItem.command(mails.allSatisfy(\.starred) ? "取消星标" : "添加星标", icon: .star) {
      store.updateMessages(mails, changes: ["starred": !mails.allSatisfy(\.starred)])
    }
    if mails.count == 1, let message = mails.first {
      CossMenuItem.command("加入清单", icon: .listCheck) { store.collectFollowUp(message: message) }
      CossMenuItem.command("稍后处理", icon: .clock) { store.collectFollowUp(message: message, snooze: true) }
    }
    CossMenuItem.submenu("标签", icon: .tag, items: mailLabelMenu(store: store, messages: mails))
    CossMenuItem.divider
    if mails.allSatisfy({ $0.folder == "trash" || $0.folder == "archive" }) {
      CossMenuItem.command("恢复原处", icon: .arrowBackUp) { store.restoreMessages(mails) }
    }
    if mails.contains(where: { $0.folder != "archive" && $0.folder != "trash" }) {
      CossMenuItem.command("归档", icon: .archive) {
        store.updateMessages(mails.filter { $0.folder != "trash" }, changes: ["folder": "archive"])
      }
    }
    CossMenuItem.command("删除邮件", icon: .trash, shortcut: "⌫",
      enabled: !mails.allSatisfy { $0.folder == "trash" }, destructive: true) {
      store.updateMessages(mails.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
    }
  }
}

struct MailRow: View {
  let message: MailMessage
  var labels: [MailCategory] = []
  var compactLabels = false
  var labelMenu: () -> [CossMenuItem] = { [] }
  var searchAccount: String? = nil
  var senderGroup: MailSenderGroup? = nil
  var isSenderChild = false
  var expanded = false
  var toggleGroup: (() -> Void)? = nil
  private var rowLabel: String {
    "\(message.sender)，\(message.subject.isEmpty ? "无主题" : message.subject)，\(accessibilityStatus)"
  }
  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      if let toggleGroup {
        Button(action: toggleGroup) {
          AppicaIcon(.chevronRightBold, size: UILayout.smallIconSize)
            .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(Palette.muted)
            .frame(width: senderDisclosureSize, height: senderDisclosureSize).contentShape(Rectangle())
        }.buttonStyle(ControlFeedback(corner: UILayout.iconRadius, showsInteractionBackground: false))
          .controlFocus(corner: UILayout.iconRadius).padding(.top, -4)
          .cossTooltip("\(expanded ? "折叠" : "展开") \(message.sender) 的 \(senderGroup?.count ?? 0) 封邮件")
          .accessibilityLabel("\(expanded ? "折叠" : "展开") \(message.sender) 的 \(senderGroup?.count ?? 0) 封邮件")
          .accessibilityValue(expanded ? "已展开" : "已折叠")
      } else if senderGroup != nil {
        Color.clear.frame(width: senderDisclosureSize, height: 1).accessibilityHidden(true)
      }
      Circle().fill(message.unread ? Palette.accent : .clear).frame(width: 6, height: 6).padding(.top, 5)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        if !isSenderChild {
          HStack(spacing: 6) {
            Text(message.sender).font(.system(size: 12, weight: message.unread ? .semibold : .regular)).lineLimit(1)
            if let group = senderGroup, group.count > 1 {
              senderGroupCount(group)
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
          if message.starred { AppicaIcon(.starFilled, size: UILayout.compactIconSize).foregroundStyle(Palette.amber) }
          if !message.attachmentIds.isEmpty {
            AppicaIcon(.paperclip, size: UILayout.compactIconSize).foregroundStyle(Palette.muted).cossTooltip("\(message.attachmentIds.count) 个附件")
          }
        }
        HStack(spacing: 8) {
          Text(previewText).font(UIType.caption).foregroundStyle(Palette.muted)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
          if let first = labels.first {
            if compactLabels {
              labelTrigger(nil)
            } else {
              HStack(spacing: 4) {
                Tag(text: first.name, tone: CategoryTone(hex: CategoryTone.hex(for: first.name, category: first)))
                  .lineLimit(1).frame(maxWidth: 88).clipped()
                if labels.count > 1 { labelTrigger("+\(labels.count - 1)") }
              }.fixedSize(horizontal: true, vertical: false)
            }
          }
        }
        if let searchAccount {
          Text("\(searchAccount) · \(MailDestination.title(forFolder: message.folder) ?? message.folder)")
            .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
        }
      }.accessibilityElement(children: .contain).accessibilityLabel(rowLabel)
        .accessibilityHint(message.preview)
    }.padding(.horizontal, mailRowHorizontalInset).padding(.vertical, isSenderChild ? 8 : 12)
      .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.ink)
      .accessibilityElement(children: .contain)
  }
  private func senderGroupCount(_ group: MailSenderGroup) -> some View {
    let hasUnread = group.unreadCount > 0
    let title = hasUnread ? "\(group.count) 封 · \(group.unreadCount) 未读" : "\(group.count) 封"
    return Text(title).font(.system(size: 11, weight: .medium)).monospacedDigit()
      .foregroundStyle(hasUnread ? Palette.accent : Palette.muted).lineLimit(1)
      .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 4)
      .background(hasUnread ? Palette.accentSoft : Palette.canvas,
        in: RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous))
      .accessibilityHidden(true)
  }

  private func labelTrigger(_ count: String?) -> some View {
    CossMenu(title: "邮件标签", value: labels.map(\.name).joined(separator: "、"), items: labelMenu) {
      if let count {
        Text(count).font(UIType.small).foregroundStyle(Palette.muted).padding(4)
      } else {
        AppicaIcon(.tag, size: UILayout.compactIconSize).foregroundStyle(Palette.muted).padding(4)
      }
    }
  }

  private var previewText: String {
    if let snippet = message.searchSnippet { return snippet }
    return message.preview
  }
  private var accessibilityStatus: String {
    var parts = [message.unread ? "此邮件未读" : "此邮件已读", displayTime(message.date)]
    if !message.attachmentIds.isEmpty { parts.append("\(message.attachmentIds.count) 个附件") }
    if message.starred { parts.append("已加星标") }
    parts.append(contentsOf: labels.map(\.name))
    if let searchAccount { parts.append(searchAccount) }
    if let group = senderGroup, group.count > 1 {
      parts.append("同一发件人共 \(group.count) 封，\(group.unreadCount) 封未读，\(expanded ? "已展开" : "已折叠")")
    }
    return parts.joined(separator: "，")
  }
}

struct MailListDisplayMenu: View {
  @Bindable var store: MailStore
  private var showsDrafts: Bool { store.pageMessages.first?.draftId != nil }
  var body: some View {
    CossMenu(title: "邮件列表显示方式", value: store.groupMailBySender && !showsDrafts ? "按发件人" : "逐封显示",
      width: 248) {
      CossMenuItem.heading("显示方式")
      CossMenuItem.command("按发件人", mark: .choice(store.groupMailBySender)) { store.changeSenderGrouping(true) }
      CossMenuItem.command("逐封显示", mark: .choice(!store.groupMailBySender)) { store.changeSenderGrouping(false) }
    } trigger: {
      CossMenuLabel(title: store.groupMailBySender && !showsDrafts ? "发件人" : "逐封",
        color: Palette.muted)
    }.fixedSize().disabled(showsDrafts || store.mailActionInProgress)
      .cossTooltip(showsDrafts ? "草稿搜索逐封显示" : "按发件人聚合或逐封显示，均按最新时间排列")
  }
}

struct MailSenderGroupFooter: View {
  @Bindable var store: MailStore
  let group: MailSenderGroup
  var body: some View {
    if store.senderGroupLoading.contains(group.id) || store.senderGroupErrors[group.id] != nil
      || store.senderGroupNextOffsets[group.id] != nil {
      HStack(spacing: 8) {
        if store.senderGroupLoading.contains(group.id) {
          CossSpinner(size: 14)
          Text("正在加载较早邮件…").font(UIType.small).foregroundStyle(Palette.muted)
        } else if let error = store.senderGroupErrors[group.id] {
          Text("较早邮件加载失败").font(UIType.small).foregroundStyle(Palette.amber).cossTooltip(error)
          ActionButton(title: "重试", color: Palette.accent, size: .compact) {
            Task { await store.loadSenderGroup(group.id, reset: store.senderGroupNextOffsets[group.id] == nil) }
          }
        } else {
          ActionButton(title: "更早邮件", color: Palette.accent, size: .compact) {
            Task { await store.loadSenderGroup(group.id, reset: false) }
          }
        }
        Spacer(minLength: 0)
        Text("\(store.senderLoadedCount(group))/\(group.count)").font(UIType.small).monospacedDigit()
          .foregroundStyle(Palette.muted)
      }.padding(.horizontal, mailRowHorizontalInset).padding(.vertical, 4).frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
          Rectangle().fill(Palette.softBorder).frame(width: 1).offset(x: -senderBranchOffset)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
  }
}
