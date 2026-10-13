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
          Text("\(store.filteredMessages.count) 封邮件").font(.system(size: 10)).foregroundStyle(
            Palette.muted)
          Spacer()
          Menu {
            Button("全部标记已读") {
              for message in store.filteredMessages.filter(\.unread) {
                store.update(message, ["unread": false])
              }
            }
            Button("刷新") { Task { await store.syncAll() } }
          } label: {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.muted)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        HStack(spacing: 6) {
          ForEach(["全部", "未读", "有附件", "AI 已总结"], id: \.self) { filter in
            Button {
              store.filter = filter
              store.selectedMessageId = store.filteredMessages.first?.id
            } label: {
              Text(filter).font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 5)
                .foregroundStyle(
                  store.filter == filter
                    ? (filter == "AI 已总结" ? Palette.purple : Palette.blue) : Palette.muted
                ).background(
                  store.filter == filter
                    ? (filter == "AI 已总结" ? Palette.purpleSoft : Palette.blueSoft) : .clear,
                  in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
          }
        }
      }.padding(14)
      if store.search.isEmpty && store.destination == .inbox {
        Button {
          store.navigate(.summary)
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "sparkles")
            VStack(alignment: .leading, spacing: 3) {
              Text("今日 AI 摘要").font(.system(size: 12, weight: .medium))
              Text("\(store.accountMessages.filter{$0.summary != nil}.count) 封已总结 · 查看邮件要点与待办")
                .font(.system(size: 10))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10))
          }.foregroundStyle(Palette.purple).padding(.horizontal, 14).frame(height: 50).background(
            Palette.purpleSoft)
        }.buttonStyle(.plain)
      }
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(store.filteredMessages) { message in
            MailRow(message: message, selected: message.id == store.selectedMessageId).contentShape(
              Rectangle()
            ).onTapGesture { store.select(message) }.contextMenu {
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
      if store.filteredMessages.isEmpty {
        Text("没有匹配的邮件").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(30)
      }
    }.background(.white)
  }
}
struct MailRow: View {
  let message: MailMessage
  var selected = false
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle().fill(message.unread ? Palette.blue : .clear).frame(width: 7, height: 7).padding(
        .top, 5)
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(message.sender).font(
            .system(size: 13, weight: message.unread ? .semibold : .regular)
          ).lineLimit(1)
          Spacer()
          Text(displayTime(message.date)).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        Text(message.subject).font(.system(size: 12, weight: message.unread ? .semibold : .regular))
          .lineLimit(1)
        Text(message.preview).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
          .lineSpacing(3)
        HStack(spacing: 6) {
          if message.category != "未分类" { Tag(text: message.category) }
          if !message.attachmentIds.isEmpty {
            Label(String(message.attachmentIds.count), systemImage: "paperclip").font(
              .system(size: 10)
            ).foregroundStyle(Palette.muted)
          }
          if message.summary != nil { Tag(text: "AI 已总结", ai: true) }
          if message.starred {
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.amber)
          }
        }
      }
    }.padding(.horizontal, 14).padding(.vertical, 13).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(selected ? Palette.blueSoft : .white).overlay(alignment: .bottom) {
      Rectangle().fill(Palette.softBorder).frame(height: 1)
    }
  }
}
