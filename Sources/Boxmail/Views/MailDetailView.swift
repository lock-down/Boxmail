import AppKit
import BoxmailCore
import SwiftUI

struct MailDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @ViewState private var loadedHistory: MailHistory?
  @ViewState private var historyMessageId: String?
  @ViewState private var presentedHistory: HistoryPresentation?
  private struct HistoryPresentation: Identifiable {
    let id, subject: String
    let history: MailHistory?
    let summary: MailSummary?
  }
  @ViewState private var historySource: HistorySource?
  private enum HistorySource { case mail(String), attachment(String) }
  private var history: MailHistory? { historyMessageId == message.id ? loadedHistory : nil }
  private var historicalSummary: MailSummary? {
    guard message.summaryHidden != true else { return nil }
    if let previous = message.previousAttachmentSummary { return previous }
    guard let summary = message.summary, summary.context != nil || !summary.keyInfo.isEmpty || summary.points.count > 1
    else { return nil }
    return summary
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        if message.folder == "trash" || message.folder == "archive" {
          ActionButton(title: message.folder == "trash" ? "恢复" : "取消归档", icon: .arrowBackUp) {
            store.restoreMessages([message])
          }.cossTooltip(message.folder == "trash" ? message.restoreTitle : message.unarchiveTitle)
        } else {
          ActionButton(title: "回复", icon: .arrowBackUp) {
            store.newDraft(reply: message)
          }
        }
        IconMenu(icon: .chevronDown, help: "更多回复选项") {
          CossMenuItem.command("全部回复", icon: .arrowBackUpDouble) { store.newDraft(reply: message, all: true) }
        }
        ActionButton(title: "转发", icon: .arrowForwardUp) {
          store.newDraft(reply: message, forward: true)
        }
        Spacer(minLength: 4)
        if message.folder != "archive" && message.folder != "trash" {
          IconButton(icon: .archive, help: "归档（Control-Command-A）") {
            store.update(message, ["folder": "archive"])
          }
        }
        IconMenu(icon: .tag, help: "编辑邮件标签") {
          mailLabelMenu(store: store, messages: [message])
        }
        if message.folder != "trash" {
          IconButton(icon: .trash, help: "移到已删除（Delete）") {
            store.update(message, ["folder": "trash"])
          }
        }
        IconButton(icon: message.starred ? .starFilled : .star, help: message.starred ? "取消星标" : "添加星标",
          color: message.starred ? Palette.amber : Palette.muted, selected: message.starred) {
          store.update(message, ["starred": !message.starred])
        }
        IconMenu(icon: .dots, help: "更多邮件操作") {
          CossMenuItem.command("加入清单", icon: .listCheck) { store.collectFollowUp(message: message) }
          CossMenuItem.command("稍后处理", icon: .clock) { store.collectFollowUp(message: message, snooze: true) }
          if history?.isEmpty == false || historicalSummary != nil {
            CossMenuItem.command("历史结果", icon: .history) {
              presentedHistory = .init(id: message.id, subject: message.subject, history: history, summary: historicalSummary)
            }
          }
          CossMenuItem.divider
          CossMenuItem.command("复制正文", icon: .copy) { NSPasteboard.general.copy(message.body) }
          CossMenuItem.command(message.unread ? "标记已读" : "标记未读", icon: .mail) {
            store.update(message, ["unread": !message.unread])
          }
        }
      }.padding(.horizontal, 12).frame(height: 48).background(Palette.paper)
        .disabled(store.mailActionInProgress)
      CossSeparator()
      ScrollViewReader { reader in
        OverlayScrollView {
          ConversationTimelineView(store: store, selected: message) { selectedContent }
            .frame(maxWidth: UILayout.reading, alignment: .leading)
            .padding(.horizontal, UILayout.pageInset).padding(.vertical, 24).frame(
              maxWidth: .infinity, alignment: .top)
        }.defaultScrollAnchor(.top).id(message.id).background(.white)
          .task(id: "\(message.id)-\(store.mailAITab?.rawValue ?? "")") {
            if store.mailAITab == .attachment {
              withAnimation(UIMotion.disclosure(reduceMotion)) { reader.scrollTo("mail-attachments", anchor: .top) }
            }
          }
      }
    }.background(.white).task(id: message.id) { await store.prepareTranslation(message) }
      .task(id: "\(store.restoreRevision)-\(message.id)") {
        let id = message.id
        let result: MailHistory? = try? await store.backend.request("/messages/\(id)/history")
        guard !Task.isCancelled else { return }
        loadedHistory = result
        historyMessageId = id
      }
      .sheet(item: $presentedHistory, onDismiss: openHistorySource) { presentation in
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            PageHeading(title: "历史结果", subtitle: presentation.subject)
            Spacer()
            IconButton(icon: .x, help: "关闭历史结果") { presentedHistory = nil }
          }
          CossSeparator()
          OverlayScrollView {
            MailHistoryView(store: store, history: presentation.history, summary: presentation.summary,
              openMail: { historySource = .mail($0); presentedHistory = nil },
              openAttachment: { historySource = .attachment($0); presentedHistory = nil })
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(24).frame(width: 620, height: 480).background(Palette.paper)
      }
  }

  private func openHistorySource() {
    switch historySource {
    case .mail(let id): if id != message.id { store.openSourceMessage(id) }
    case .attachment(let id): store.previewSourceAttachment(id)
    case nil: break
    }
    historySource = nil
  }

  private var selectedContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(message.subject.isEmpty ? "（无主题）" : message.subject)
        .font(.system(size: 22, weight: .semibold)).tracking(-0.4).lineSpacing(4)
        .textSelection(.enabled).accessibilityAddTraits(.isHeader)
        .fixedSize(horizontal: false, vertical: true)
      if !store.labels(for: message).isEmpty {
        WrappingFlowLayout(spacing: 6) {
          ForEach(store.labels(for: message)) { label in
            Tag(text: label.name, tone: store.categoryTone(label.name))
          }
        }
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
      MailTranslationControls(store: store, message: message).id("mail-body")
      QuoteCollapsingBodyView(message: store.translatedMessage(message), preferences: store.settings.preferences,
        updatesTextOnly: true).id(message.id)
      if !message.attachmentIds.isEmpty {
        MailAttachmentSection(store: store, message: message).id("mail-attachments")
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: store.mailAITab)
  }
}
