import BoxmailCore
import SwiftUI

struct MailListView: View {
  @Bindable var store: MailStore
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(store.search.isEmpty ? store.destination.title : "搜索结果").font(
            .system(size: 14, weight: .semibold))
          Text("\(store.pageTotal)").font(.system(size: 11, weight: .medium))
            .monospacedDigit().foregroundStyle(
              Palette.muted)
          Spacer()
          IconMenu(icon: "line.3.horizontal.decrease", help: "邮件列表操作") {
            Button("全部标记已读") {
              for message in store.filteredMessages.filter(\.unread) {
                store.update(message, ["unread": false])
              }
            }
            Button("刷新") { Task { await store.syncAll() } }
          }
        }
        FilterBar(values: ["全部", "未读", "有附件", "AI 已总结"], selection: $store.filter, compact: true) { _ in
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
              Text("\(store.accountMessages.filter{$0.summary != nil}.count) 封已总结 · 查看邮件要点与待办")
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
        EmptyState(title: "没有匹配的邮件", subtitle: "调整筛选条件，或搜索其他关键词。", icon: "tray")
      } else {
        OverlayScrollView {
          LazyVStack(spacing: 0) {
            ForEach(store.filteredMessages) { message in
              Button {
                store.select(message)
              } label: {
                MailRow(message: message, selected: message.id == store.selectedMessageId)
              }.buttonStyle(
                ControlFeedback(selected: message.id == store.selectedMessageId, corner: 0)
              )
              .accessibilityAddTraits(message.id == store.selectedMessageId ? .isSelected : [])
              .controlFocus(corner: 0)
              .contextMenu {
                Button(message.starred ? "取消星标" : "添加星标") {
                  store.update(message, ["starred": !message.starred])
                }
                Button(message.unread ? "标记已读" : "标记未读") {
                  store.update(message, ["unread": !message.unread])
                }
                Button("回复") { store.newDraft(reply: message) }
                Button("移到已删除") { store.update(message, ["folder": "trash"]) }
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
        if let progress = store.currentSyncFolder {
          if let loaded = progress.downloaded, let total = progress.total {
            Text("已缓存 \(loaded) / \(total) 封").font(.system(size: 11)).foregroundStyle(
              Palette.muted)
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
        if let failure = store.syncSnapshot?.results.first(where: {
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
  }
}
struct MailRow: View {
  let message: MailMessage
  var selected = false
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
        Text(message.preview).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(2)
          .lineSpacing(3)
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
