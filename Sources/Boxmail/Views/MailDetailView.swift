import AppKit
import BoxmailCore
import SwiftUI

struct MailDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        if message.folder == "trash" || message.folder == "archive" {
          ActionButton(title: message.folder == "trash" ? "恢复" : "取消归档", icon: .arrowGoBackLine) {
            store.restoreMessages([message])
          }.cossTooltip(message.folder == "trash" ? message.restoreTitle : message.unarchiveTitle)
        } else {
          ActionButton(title: "回复", icon: .replyLine, emphasis: .secondary) {
            store.newDraft(reply: message)
          }
        }
        IconMenu(icon: .arrowDownSLine, help: "更多回复选项") {
          CossMenuItem.command("全部回复", icon: .replyAllLine) { store.newDraft(reply: message, all: true) }
        }
        ActionButton(title: "转发", icon: .shareForwardLine) {
          store.newDraft(reply: message, forward: true)
        }
        Spacer(minLength: 4)
        if message.folder != "archive" && message.folder != "trash" {
          IconButton(icon: .archiveLine, help: "归档（Control-Command-A）", size: 28) {
            store.update(message, ["folder": "archive"])
          }
        }
        IconMenu(icon: .priceTag3Line, help: "分类邮件") {
          for category in store.categories {
            CossMenuItem.command(category.name, mark: .choice(message.category == category.name)) {
              store.update(message, ["category": category.name])
            }
          }
        }
        if message.folder != "trash" {
          IconButton(icon: .deleteBin6Line, help: "移到已删除（Delete）", size: 28) {
            store.update(message, ["folder": "trash"])
          }
        }
        IconButton(icon: message.starred ? .starFill : .starLine, help: message.starred ? "取消星标" : "添加星标",
          color: message.starred ? Palette.amber : Palette.muted, size: 28, selected: message.starred) {
          store.update(message, ["starred": !message.starred])
        }
        IconMenu(icon: .moreLine, help: "更多邮件操作") {
          CossMenuItem.command("收录跟进", icon: .listCheck3) { store.collectFollowUp(message: message) }
          CossMenuItem.command("稍后处理…", icon: .timeLine) { store.collectFollowUp(message: message, snooze: true) }
          CossMenuItem.divider
          CossMenuItem.command("向助手询问此邮件", icon: .chatAiLine) { store.assistant.begin(scope: .init(kind: "message", messageId: message.id)) }
          CossMenuItem.command("向助手询问此会话", icon: .discussLine) { store.assistant.begin(scope: .init(kind: "conversation", messageId: message.id)) }
          CossMenuItem.divider
          CossMenuItem.command("复制邮件正文", icon: .fileCopyLine) { NSPasteboard.general.copy(message.body) }
          CossMenuItem.command(message.unread ? "标记已读" : "标记未读", icon: .mailLine) {
            store.update(message, ["unread": !message.unread])
          }
        }
      }.padding(.horizontal, 12).frame(height: 48).background(Palette.paper)
        .disabled(store.mailActionInProgress)
      CossSeparator()
      MailAIBar(store: store, message: message)
        .disabled(store.mailActionInProgress)
      CossSeparator()
      ScrollViewReader { reader in
        OverlayScrollView {
          ConversationTimelineView(store: store, selected: message) {
            selectedContent {
              withAnimation(UIMotion.disclosure(reduceMotion)) { reader.scrollTo("mail-body", anchor: .top) }
            }
          }
            .frame(maxWidth: UILayout.reading, alignment: .leading)
            .padding(.horizontal, UILayout.pageInset).padding(.vertical, 24).frame(
              maxWidth: .infinity, alignment: .top)
        }.defaultScrollAnchor(.top).id(message.id).background(.white)
          .task(id: "\(message.id)-\(store.mailAITab?.rawValue ?? "")") {
            if let tab = store.mailAITab {
              withAnimation(UIMotion.disclosure(reduceMotion)) {
                reader.scrollTo(tab == .attachment ? "mail-attachments" : tab == .translate ? "mail-body" : "mail-assistant", anchor: .top)
              }
            }
          }
      }
    }.background(.white)
  }
  private func selectedContent(showOriginal: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(message.subject.isEmpty ? "（无主题）" : message.subject)
        .font(.system(size: 22, weight: .semibold)).tracking(-0.4).lineSpacing(4)
        .textSelection(.enabled).accessibilityAddTraits(.isHeader)
        .fixedSize(horizontal: false, vertical: true)
      if message.category != "未分类" {
        Tag(text: message.category, tone: store.categoryTone(message.category))
      }
      HStack(alignment: .top, spacing: 11) {
        SenderAvatar(name: message.sender, size: 32)
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message.sender).font(.system(size: 13, weight: .semibold)).lineLimit(1)
              .layoutPriority(1).cossTooltip(message.sender)
            if !message.senderEmail.isEmpty && message.sender.caseInsensitiveCompare(message.senderEmail) != .orderedSame {
              Text(message.senderEmail).font(UIType.small).foregroundStyle(Palette.muted)
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle).cossTooltip(message.senderEmail)
            }
            Spacer(minLength: 8)
            Text(displayTime(message.date)).font(.system(size: 11)).monospacedDigit()
              .foregroundStyle(Palette.muted).fixedSize()
          }
          Text("账户：" + (store.accounts.first { $0.id == message.accountId }?.email ?? "来源账户")).font(UIType.small).foregroundStyle(Palette.muted)
          RecipientDetailsView(to: message.to, cc: message.cc).id(message.id)
        }
      }
      if let tab = store.mailAITab, tab != .attachment, tab != .translate {
        MailAssistantView(store: store, message: message, tab: tab, showOriginal: showOriginal).id("mail-assistant")
          .transition(UIMotion.reveal(reduceMotion))
      }
      HStack(spacing: 12) {
        Text(store.isShowingTranslation(message) ? "简体中文译文" : "邮件原文").font(UIType.small).foregroundStyle(Palette.muted)
        Rectangle().fill(Palette.softBorder).frame(height: 1)
        if store.isShowingTranslation(message) {
          if message.translation != nil || store.aiOutput(task: "translate", messageId: message.id)?.text.isEmpty == false {
            CopyButton(help: "复制译文") { store.translatedMessage(message).body }
          }
          if let output = store.aiOutput(task: "translate", messageId: message.id), output.status == "running" {
            CossSpinner(size: 12)
            Text(output.stage ?? "正在翻译…").font(UIType.small).foregroundStyle(Palette.muted)
          }
          ActionButton(title: message.translation == nil ? "生成译文" : "重新翻译", icon: .refreshLine) {
            store.generate(task: "translate", message: message)
          }.disabled(store.busy.contains("agent"))
        }
      }.id("mail-body")
      if store.isShowingTranslation(message), let error = store.mailAIErrors[message.id] {
        Label(error, icon: .errorWarningLine).font(UIType.small).foregroundStyle(Palette.amber)
      }
      if store.isShowingTranslation(message), message.translation == nil,
        store.aiOutput(task: "translate", messageId: message.id) == nil {
        Text("生成译文后在此阅读，当前仍显示邮件原文。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
      QuoteCollapsingBodyView(message: store.translatedMessage(message), preferences: store.settings.preferences,
        updatesTextOnly: true).id(message.id)
      if !message.attachmentIds.isEmpty {
        MailAttachmentSection(store: store, message: message).id("mail-attachments")
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: store.mailAITab)
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
            .truncationMode(.middle).cossTooltip(attachment.name)
          HStack {
            Text(fileSize(attachment.size)).font(UIType.small).foregroundStyle(Palette.muted)
            if let item = batchItem {
              Text(itemTitle(item)).foregroundStyle(
                ["failed", "unsupported"].contains(item.status) ? Palette.amber : Palette.accent)
                .font(.system(size: 11, weight: .medium)).cossTooltip(item.error ?? itemTitle(item))
            } else if attachment.isAnalyzed {
              Tag(text: "AI 已解析", ai: true)
            } else if attachment.canAnalyze {
              Tag(text: attachment.isArchive || attachment.isImage || attachment.isPDF || attachment.isPresentation ? "可 AI 理解" : "已提取文本", ai: true)
            }
          }
          if let item = batchItem, item.status == "failed", let error = item.error {
            Text(error).font(UIType.small).foregroundStyle(Palette.amber).lineLimit(2).cossTooltip(error)
          }
        }
        Spacer(minLength: 0)
      }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
    }.buttonStyle(ControlFeedback()).controlFocus()
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
