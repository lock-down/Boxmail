import BoxmailCore
import SwiftUI

struct MailListView: View {
  @Bindable var store: MailStore
  @ViewState<MailAccount?> private var trashAccount: MailAccount?
  private var emptyingTrash: Bool { store.busy.contains("empty-trash-\(store.accountId)") }
  private var emptyFolderHint: String {
    if store.busy.contains("sync") { return "正在同步，请等待服务器返回邮件。" }
    if [.inbox, .sent].contains(store.destination), store.currentAccount?.isDemo == false,
      ["imap.163.com", "imap.126.com", "imap.yeah.net"].contains(store.currentAccount?.imapHost.lowercased() ?? ""),
      store.currentSyncFolder?.total == 0
    {
      return "若网页版有历史邮件，请在网易邮箱的 POP3/SMTP/IMAP 设置中选择“收取全部邮件”，保存后重新同步。"
    }
    return "点击顶部同步按钮获取邮件。"
  }
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(store.search.isEmpty ? store.destination.title : "搜索结果").font(
            .system(size: 14, weight: .semibold))
          Text("\(store.pageTotal)").font(.system(size: 11, weight: .medium))
            .monospacedDigit().foregroundStyle(
              Palette.muted)
          Spacer()
          if store.destination == .trash {
            Button {
              trashAccount = store.currentAccount
            } label: {
              HStack(spacing: 4) {
                if emptyingTrash { ProgressView().controlSize(.mini) }
                Text(emptyingTrash ? "正在清空…" : "清空")
                  .font(.system(size: 12, weight: .medium))
              }.foregroundStyle(Palette.ink).padding(.horizontal, 8).frame(height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(ControlFeedback()).controlFocus()
              .help("清空当前账户的所有已删除邮件")
              .accessibilityLabel("清空已删除邮件")
              .disabled(emptyingTrash || store.currentAccount == nil
                || (store.currentAccount?.isDemo == true && store.trashMessages.isEmpty)
                || store.busy.contains("sync"))
          }
          IconMenu(icon: "line.3.horizontal.decrease", help: "邮件列表操作") {
            Button("全部标记已读") {
              for message in store.filteredMessages.filter(\.unread) {
                store.update(message, ["unread": false])
              }
            }
            Button("刷新") { Task { await store.syncAll() } }
          }
        }
        FilterBar(values: ["全部", "未读", "有附件", "AI 已总结"], selection: $store.filter, fillsWidth: true) { _ in
          store.selectedMessageId = store.filteredMessages.first?.id
        }
      }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
      if store.search.isEmpty && store.destination == .inbox {
        Button {
          store.navigate(.summary)
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "sparkles")
            VStack(alignment: .leading, spacing: 3) {
              Text("邮件摘要").font(.system(size: 12, weight: .medium))
              Text("\(store.summaryOverviewMessages.count) 封已收录 · 查看邮件要点与待办")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10))
          }.foregroundStyle(Palette.accent).padding(.horizontal, 16).frame(height: 54).background(
            Palette.blueSoft.opacity(0.4)
          ).contentShape(Rectangle())
        }.buttonStyle(ControlFeedback(corner: 0)).controlFocus(corner: 0)
      }
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
        OverlayScrollView {
          LazyVStack(spacing: 0) {
            ForEach(store.filteredMessages) { message in
              Button {
                store.select(message)
              } label: {
                MailRow(message: message, selected: message.id == store.selectedMessageId,
                  searchAccount: store.search.isEmpty ? nil : store.accounts.first(where: { $0.id == message.accountId })?.email)
              }.buttonStyle(
                ControlFeedback(selected: message.id == store.selectedMessageId, corner: 0)
              )
              .accessibilityAddTraits(message.id == store.selectedMessageId ? .isSelected : [])
              .controlFocus(corner: 0)
              .contextMenu {
                if let draftID = message.draftId {
                  Button("继续编辑草稿") { store.editDraft(draftID) }
                    .disabled(store.drafts.first(where: { $0.id == draftID })?.status == "sending")
                } else {
                Button(message.starred ? "取消星标" : "添加星标") {
                  store.update(message, ["starred": !message.starred])
                }
                Button(message.unread ? "标记已读" : "标记未读") {
                  store.update(message, ["unread": !message.unread])
                }
                Button("回复") { store.newDraft(reply: message) }
                Menu("分类") {
                  ForEach(store.categories) { category in
                    Button { store.update(message, ["category": category.name]) } label: {
                      if message.category == category.name { Label(category.name, systemImage: "checkmark") }
                      else { Text(category.name) }
                    }
                  }
                }
                if message.folder == "trash" {
                  Button(message.restoreTitle) { store.restore(message) }
                    .disabled(emptyingTrash || store.busy.contains("message-\(message.id)"))
                } else {
                  if message.folder == "archive" {
                    Button(message.unarchiveTitle) { store.unarchive(message) }
                      .disabled(store.busy.contains("message-\(message.id)"))
                  }
                  Button("移到已删除") { store.update(message, ["folder": "trash"]) }
                }
                }
              }
            }
          }
        }.defaultScrollAnchor(.top)
          .id("\(store.accountId)-\(store.destination.rawValue)-\(store.filter)-\(store.search)")
      }
      Divider().overlay(Palette.softBorder)
      VStack(spacing: 9) {
        if store.listLoading {
          ProgressView("正在加载邮件…").controlSize(.small)
        }
        if let error = store.listError {
          Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber)
          ActionButton(title: "重新加载列表", icon: "arrow.clockwise") {
            Task { await store.loadMessages(reset: true, preserveSelection: true) }
          }
        } else if store.nextOffset != nil {
          ActionButton(title: "显示更多邮件", icon: "chevron.down") {
            Task { await store.loadMessages(reset: false) }
          }.disabled(store.listLoading)
        }
        if !store.search.isEmpty {
          Text("搜索仅覆盖本机已缓存邮件，索引会自动更新。")
            .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
          if store.searchIndex?.partial == true {
            Text("部分历史邮件尚未缓存，继续同步可扩大搜索范围。")
              .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
          }
        } else if [.inbox, .sent, .trash, .archive].contains(store.destination) {
          Text("\(store.destination.title)：本机缓存 \(store.cachedMessageCount(accountId: store.accountId, folder: store.destination.rawValue)) 封")
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        if store.search.isEmpty, let progress = store.currentSyncFolder {
          if let total = progress.total {
            Text("上次同步服务器共 \(total) 封").font(.system(size: 11)).foregroundStyle(Palette.muted)
          }
          if let error = progress.lastError {
            Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber)
              .fixedSize(horizontal: false, vertical: true)
          }
          if progress.hasMore == true || ["failed", "paused"].contains(progress.status) {
            ActionButton(title: "继续同步历史邮件", icon: "arrow.down.circle") {
              Task { await store.syncAll(folder: progress.folder) }
            }.disabled(store.busy.contains("sync"))
          }
        }
        if store.search.isEmpty, let failure = store.syncSnapshot?.results.first(where: {
          $0.accountId == store.accountId && $0.status == "failed"
        }), store.currentSyncFolder?.lastError == nil {
          Text(failure.error ?? "同步未完成，请重试").font(.system(size: 11))
            .foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
          ActionButton(title: "重试同步", icon: "arrow.clockwise") {
            Task { await store.syncAll() }
          }.disabled(store.busy.contains("sync"))
        }
      }.padding(12).frame(maxWidth: .infinity).background(Palette.canvas)
    }.background(.white)
      .alert("清空已删除邮件？", isPresented: Binding(
        get: { trashAccount != nil }, set: { if !$0 { trashAccount = nil } }),
        presenting: trashAccount
      ) { account in
        Button("取消", role: .cancel) { trashAccount = nil }
        Button("清空已删除", role: .destructive) {
          store.emptyTrash(account: account)
          trashAccount = nil
        }
      } message: { account in
        Text("将永久删除 \(account.email) 中的所有已删除邮件及不再使用的附件，包括未显示的邮件。"
          + (account.isDemo ? "此操作无法恢复。" : "此操作会同步到邮箱服务器，无法恢复。"))
      }
  }
}
struct MailRow: View {
  let message: MailMessage
  var selected = false
  var searchAccount: String? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle().fill(message.unread ? Palette.blue : .clear).frame(width: 7, height: 7).padding(
        .top, 5)
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(message.sender).font(
            .system(size: 12, weight: message.unread ? .semibold : .medium)
          ).lineLimit(1)
          Spacer()
          Text(displayTime(message.date)).font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(Palette.muted).fixedSize()
        }
        Text(message.subject).font(.system(size: 13, weight: message.unread ? .semibold : .medium))
          .lineLimit(1)
        Text(message.searchSnippet ?? message.preview).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(2)
          .lineSpacing(3)
        if let searchAccount {
          Text("\(searchAccount) · \(MailDestination(rawValue: message.folder)?.title ?? (message.folder == "spam" ? "垃圾邮件" : message.folder))")
            .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
        }
        HStack(spacing: 6) {
          if message.category != "未分类" { Tag(text: message.category) }
          if !message.attachmentIds.isEmpty {
            Label(String(message.attachmentIds.count), systemImage: "paperclip").font(
              .system(size: 11)
            ).foregroundStyle(Palette.muted)
          }
          if message.summary != nil { Tag(text: "AI 已总结", ai: true) }
          if message.starred {
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.amber)
          }
        }
      }
    }.padding(.horizontal, 16).padding(.vertical, 15).frame(
      maxWidth: .infinity, alignment: .leading
    ).foregroundStyle(Palette.ink).contentShape(Rectangle())
      .background(selected ? Palette.blueSoft : .white).overlay(alignment: .leading) {
        if selected { Rectangle().fill(Palette.blue).frame(width: 1) }
      }.overlay(alignment: .bottom) {
        Rectangle().fill(Palette.softBorder).frame(height: 1)
      }
      .animation(UIMotion.selection(reduceMotion), value: selected)
  }
}
