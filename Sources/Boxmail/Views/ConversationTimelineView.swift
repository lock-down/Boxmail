import BoxmailCore
import SwiftUI

struct ConversationTimelineView<SelectedContent: View>: View {
  @Bindable var store: MailStore
  let selected: MailMessage
  @ViewBuilder let selectedContent: () -> SelectedContent

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let conversation = store.conversation, store.conversationAnchor == selected.id, conversation.total > 1 {
        VStack(alignment: .leading, spacing: 7) {
          HStack {
            Label("往来邮件 · \(conversation.total) 封", icon: .messages)
              .font(UIType.section)
            Spacer()
            Text("当前邮件置顶 · 时间倒序").font(UIType.small).foregroundStyle(Palette.muted)
          }
          Text(store.accounts.first(where: { $0.id == conversation.accountId })?.email ?? "当前账户")
            .font(UIType.small).foregroundStyle(Palette.muted).textSelection(.enabled)
          if conversation.partial {
            Text("仅包含本机已缓存的往来，继续同步历史邮件可补齐会话。")
              .font(UIType.small).foregroundStyle(Palette.muted)
          }
        }
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 8) {
            Text("当前邮件").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
            Text(MailDestination.title(forFolder: selected.folder) ?? selected.folder)
              .font(UIType.small).foregroundStyle(Palette.muted)
          }
          selectedContent()
        }.id("thread-\(selected.id)")
        CossSeparator()
        ForEach(conversation.messages.filter { $0.id != selected.id }) { header in
          ConversationMessageView(store: store, header: header).id(header.id)
          CossSeparator()
        }
        if conversation.nextOffset != nil {
          ActionButton(title: "继续加载（已显示 \(conversation.messages.count) / \(conversation.total) 封）", icon: .chevronDown, color: Palette.accent) {
            Task { await store.loadConversation(reset: false) }
          }
        }
      } else { selectedContent() }
      if let error = store.conversationError {
        VStack(alignment: .leading, spacing: 8) {
          Text("会话加载未完成：\(error)").font(UIType.small).foregroundStyle(Palette.amber)
          ActionButton(title: "重新加载会话", icon: .refresh, color: Palette.accent) { Task { await store.loadConversation() } }
        }
      }
    }
  }
}

private struct ConversationMessageView: View {
  @Bindable var store: MailStore
  let header: MailMessage
  @ViewState<Bool> private var expanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button {
        withAnimation(UIMotion.disclosure(reduceMotion)) { expanded.toggle() }
      } label: {
        HStack(alignment: .top, spacing: 12) {
          SenderAvatar(name: header.sender, size: 32)
          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
              Text(header.sender).font(.system(size: 13, weight: .medium)).lineLimit(1)
              Spacer(minLength: 12)
              Text(displayTime(header.date)).font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
            }
            HStack {
              Text(header.subject).font(UIType.caption).lineLimit(1)
              Spacer(minLength: 8)
              Text(MailDestination.title(forFolder: header.folder) ?? header.folder)
                .font(UIType.small).foregroundStyle(Palette.muted)
            }
            if !expanded {
              Text(header.preview).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          AppicaIcon(expanded ? .chevronDown : .chevronRight, size: UILayout.smallIconSize)
            .foregroundStyle(Palette.muted)
            .frame(width: 14, height: 32)
        }.foregroundStyle(Palette.ink).padding(12)
      }.buttonStyle(ControlFeedback()).controlFocus()
        .accessibilityLabel("\(expanded ? "收起" : "展开")会话邮件：\(header.sender)，\(header.subject)")
      if expanded {
        VStack(alignment: .leading, spacing: 14) {
          if let message = store.conversationBodies[header.id] {
            Text(message.senderEmail).font(UIType.small).foregroundStyle(Palette.muted).textSelection(.enabled)
            RecipientDetailsView(to: message.to, cc: message.cc)
            WrappingFlowLayout(spacing: 8) {
              ActionButton(title: "回复此封", icon: .arrowBackUp, color: Palette.accent) { store.newDraft(reply: message) }
              ActionButton(title: "打开此封邮件", icon: .arrowUpRight) { store.openMail(message) }
              if message.folder == "trash" {
                ActionButton(title: message.restoreTitle, icon: .arrowBackUp) { store.restore(message) }
              } else if message.folder == "archive" {
                ActionButton(title: "取消归档", icon: .arrowBackUp) { store.restore(message) }
              } else {
                ActionButton(title: "归档", icon: .archive) { store.update(message, ["folder": "archive"]) }
              }
            }
            QuoteCollapsingBodyView(message: message, preferences: store.settings.preferences)
            if !message.attachmentIds.isEmpty { MailAttachmentSection(store: store, message: message) }
          } else { CossSpinner(label: "正在加载这封邮件…") }
        }.padding(.leading, 54).padding(.trailing, 10)
      }
    }.task(id: "\(expanded)-\(store.restoreRevision)") {
      if expanded && store.conversationBodies[header.id] == nil { await store.loadConversationBody(header) }
    }.onChange(of: expanded) { _, value in
      if !value { store.unloadConversationBody(header.id) }
    }
  }
}

struct QuoteCollapsingBodyView: View {
  let message: MailMessage
  let preferences: Preferences
  var updatesTextOnly = false
  @ViewState<Bool> private var showingQuotes = false
  private var hasQuotes: Bool { !QuotedMailText.split(message.body).quoted.isEmpty || QuotedMailText.hasHTMLQuote(message.html) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      MailBodyView(message: message, preferences: preferences, collapseQuotes: hasQuotes && !showingQuotes,
        updatesTextOnly: updatesTextOnly)
      if hasQuotes {
        ActionButton(title: showingQuotes ? "收起引用内容" : "显示引用内容", icon: .quote) { showingQuotes.toggle() }
      }
    }
  }
}
