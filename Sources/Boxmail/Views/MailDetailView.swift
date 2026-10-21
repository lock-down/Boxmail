import AppKit
import BoxmailCore
import SwiftUI

struct MailDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          if message.folder == "trash" {
            ActionButton(title: message.restoreTitle, icon: "arrow.uturn.backward", kind: .primary) {
              store.restore(message)
            }.disabled(store.busy.contains("message-\(message.id)")
              || store.busy.contains("empty-trash-\(message.accountId)"))
          } else {
            if message.folder == "archive" {
              ActionButton(title: "取消归档", icon: "arrow.uturn.backward", kind: .primary) {
                store.unarchive(message)
              }.help(message.unarchiveTitle)
                .disabled(store.busy.contains("message-\(message.id)"))
            }
            ActionButton(title: "回复", icon: "arrowshape.turn.up.left", kind: .softAI) {
              store.newDraft(reply: message)
            }
            if message.folder != "archive" {
              ActionButton(title: "全部回复", icon: "arrowshape.turn.up.left.2") {
                store.newDraft(reply: message, all: true)
              }
              ActionButton(title: "转发", icon: "arrowshape.turn.up.right") {
                store.newDraft(reply: message, forward: true)
              }
            }
          }
        }
        Spacer(minLength: 8)
        HStack(spacing: 4) {
          if message.folder != "archive" {
            IconButton(icon: "archivebox", help: "归档") {
              store.update(message, ["folder": "archive"])
            }
          }
          IconMenu(icon: "tag", help: "分类邮件") {
            ForEach(["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来", "未分类"], id: \.self) { category in
              Button(category) { store.update(message, ["category": category]) }
            }
          }
          if message.folder != "trash" {
            IconButton(icon: "trash", help: "移到已删除") { store.update(message, ["folder": "trash"]) }
          }
          IconButton(
            icon: message.starred ? "star.fill" : "star", help: message.starred ? "取消星标" : "添加星标",
            color: message.starred ? Palette.amber : Palette.muted, active: message.starred
          ) { store.update(message, ["starred": !message.starred]) }
          IconMenu(icon: "ellipsis", help: "更多邮件操作") {
            if message.folder == "archive" {
              Button("全部回复") { store.newDraft(reply: message, all: true) }
              Button("转发") { store.newDraft(reply: message, forward: true) }
              Divider()
            }
            Button("复制邮件正文") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.body, forType: .string)
            }
            Button("标记为未读") { store.update(message, ["unread": true]) }
          }
        }
      }.padding(.horizontal, 16).frame(height: 52).background(.white)
      Divider().overlay(Palette.softBorder)
      MailAIBar(store: store, message: message)
      Divider().overlay(Palette.softBorder)
      ScrollViewReader { reader in
        OverlayScrollView {
          VStack(alignment: .leading, spacing: 22) {
            Text(message.subject).font(.system(size: 23, weight: .semibold)).tracking(-0.35).lineSpacing(4)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
            if message.category != "未分类" || message.starred {
              HStack(spacing: 6) {
                if message.category != "未分类" { Tag(text: message.category) }
                if message.starred { Tag(text: "星标邮件") }
              }
            }
            HStack(alignment: .top, spacing: 11) {
              SenderAvatar(name: message.sender, size: 34)
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(message.sender).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                  Spacer(minLength: 8)
                  Text(displayTime(message.date)).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Palette.muted).fixedSize()
                }
                Text(message.senderEmail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                  .textSelection(.enabled)
                  .lineLimit(1).truncationMode(.middle)
                RecipientDetailsView(to: message.to, cc: message.cc).id(message.id)
              }
            }
            if let tab = store.mailAITab, tab != .attachment {
              MailAssistantView(store: store, message: message, tab: tab).id("mail-assistant")
                .transition(UIMotion.reveal(reduceMotion))
            }
            HStack(spacing: 12) {
              Text("邮件原文").font(UIType.small).foregroundStyle(Palette.muted)
              Rectangle().fill(Palette.softBorder).frame(height: 1)
            }
            MailBodyView(message: message, preferences: store.settings.preferences).id(message.id)
            if !message.attachmentIds.isEmpty {
              MailAttachmentSection(store: store, message: message).id("mail-attachments")
            }
          }.animation(UIMotion.disclosure(reduceMotion), value: store.mailAITab)
            .frame(maxWidth: UILayout.reading, alignment: .leading)
            .padding(.horizontal, 30).padding(.vertical, 32).frame(
              maxWidth: .infinity, alignment: .top)
        }.defaultScrollAnchor(.top).id(message.id).background(.white)
          .task(id: "\(message.id)-\(store.mailAITab?.rawValue ?? "")") {
            if let tab = store.mailAITab {
              withAnimation(UIMotion.disclosure(reduceMotion)) {
                reader.scrollTo(tab == .attachment ? "mail-attachments" : "mail-assistant", anchor: .top)
              }
            }
          }
      }
    }.background(.white)
  }
}
struct AttachmentCard: View {
  let attachment: MailAttachment
  var batchItem: AttachmentBatchItem? = nil
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        AttachmentIcon(attachment: attachment, size: 23)
        VStack(alignment: .leading, spacing: 4) {
          Text(attachment.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .truncationMode(.middle).help(attachment.name)
          HStack {
            Text(fileSize(attachment.size)).font(UIType.small).foregroundStyle(Palette.muted)
            if let item = batchItem {
              Text(itemTitle(item)).foregroundStyle(
                ["failed", "unsupported"].contains(item.status) ? Palette.amber : Palette.accent)
                .font(.system(size: 11, weight: .medium)).help(item.error ?? itemTitle(item))
            } else if attachment.isAnalyzed {
              Tag(text: "AI 已解析", ai: true)
            } else if attachment.canAnalyze {
              Tag(text: attachment.isImage || attachment.isPDF || attachment.isPresentation ? "可 AI 理解" : "已提取文本", ai: true)
            }
          }
          if let item = batchItem, item.status == "failed", let error = item.error {
            Text(error).font(UIType.small).foregroundStyle(Palette.amber).lineLimit(2).help(error)
          }
        }
        Spacer(minLength: 0)
      }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9)).contentShape(
        RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(ControlFeedback(corner: 8)).controlFocus(corner: 8)
  }
  private func itemTitle(_ item: AttachmentBatchItem) -> String {
    switch item.status {
    case "pending": return "等待理解"
    case "running": return "正在理解…"
    case "completed": return "AI 已解析"
    case "existing": return "已有结果 · 已保留"
    case "failed": return "理解失败"
    case "unsupported": return "暂不支持"
    default: return "等待理解"
    }
  }
}
