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
            Label("往来邮件 · \(conversation.total) 封", systemImage: "bubble.left.and.bubble.right")
              .font(UIType.section)
            Spacer()
            Text("按时间排列").font(UIType.small).foregroundStyle(Palette.muted)
          }
          Text(store.accounts.first(where: { $0.id == conversation.accountId })?.email ?? "当前账户")
            .font(UIType.small).foregroundStyle(Palette.muted).textSelection(.enabled)
          if conversation.partial {
            Text("仅包含本机已缓存的往来，继续同步历史邮件可补齐会话。")
              .font(UIType.small).foregroundStyle(Palette.muted)
          }
        }
        ForEach(conversation.messages) { header in
          if header.id == selected.id {
            VStack(alignment: .leading, spacing: 14) {
              HStack(spacing: 8) {
                Text("当前邮件").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.blue)
                Text(folderTitle(header.folder)).font(UIType.small).foregroundStyle(Palette.muted)
              }
              selectedContent()
            }.id("thread-\(header.id)")
          } else {
            ConversationMessageView(store: store, header: header).id(header.id)
          }
          Divider().overlay(Palette.softBorder)
        }
        if conversation.nextOffset != nil {
          WorkflowAction(title: "继续加载（已显示 \(conversation.messages.count) / \(conversation.total) 封）", icon: "chevron.down", color: Palette.blue) {
            Task { await store.loadConversation(reset: false) }
          }
        }
      } else { selectedContent() }
      if let error = store.conversationError {
        VStack(alignment: .leading, spacing: 8) {
          Text("会话加载未完成：\(error)").font(UIType.small).foregroundStyle(Palette.amber)
          WorkflowAction(title: "重新加载会话", icon: "arrow.clockwise", color: Palette.blue) { Task { await store.loadConversation() } }
        }
      }
    }
  }
  private func folderTitle(_ folder: String) -> String { MailDestination(rawValue: folder)?.title ?? (folder == "spam" ? "垃圾邮件" : folder) }
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
              Text(MailDestination(rawValue: header.folder)?.title ?? (header.folder == "spam" ? "垃圾邮件" : header.folder))
                .font(UIType.small).foregroundStyle(Palette.muted)
            }
            if !expanded {
              Text(header.preview).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
            .frame(width: 14, height: 32)
        }.foregroundStyle(Palette.ink).padding(10).contentShape(RoundedRectangle(cornerRadius: 8))
      }.buttonStyle(ControlFeedback(corner: 8))
        .accessibilityLabel("\(expanded ? "收起" : "展开")会话邮件：\(header.sender)，\(header.subject)")
      if expanded {
        VStack(alignment: .leading, spacing: 14) {
          if let message = store.conversationBodies[header.id] {
            Text(message.senderEmail).font(UIType.small).foregroundStyle(Palette.muted).textSelection(.enabled)
            RecipientDetailsView(to: message.to, cc: message.cc)
            HStack(spacing: 12) {
              WorkflowAction(title: "回复此封", icon: "arrowshape.turn.up.left", color: Palette.blue) { store.newDraft(reply: message) }
              WorkflowAction(title: "打开此封邮件", icon: "arrow.up.right") { store.openMail(message) }
              Spacer(minLength: 0)
              if message.folder == "trash" {
                WorkflowAction(title: message.restoreTitle, icon: "arrow.uturn.backward") { store.restore(message) }
              } else if message.folder == "archive" {
                WorkflowAction(title: "取消归档", icon: "arrow.uturn.backward") { store.unarchive(message) }
              } else {
                WorkflowAction(title: "归档", icon: "archivebox") { store.update(message, ["folder": "archive"]) }
              }
            }
            QuoteCollapsingBodyView(message: message, preferences: store.settings.preferences)
            if !message.attachmentIds.isEmpty { MailAttachmentSection(store: store, message: message) }
          } else { ProgressView("正在加载这封邮件…").controlSize(.small) }
        }.padding(.leading, 54).padding(.trailing, 10)
      }
    }.task(id: "\(expanded)-\(store.conversationBodies[header.id] != nil)") {
      if expanded && store.conversationBodies[header.id] == nil { await store.loadConversationBody(header) }
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
        WorkflowAction(title: showingQuotes ? "收起引用内容" : "显示引用内容", icon: "text.quote") { showingQuotes.toggle() }
      }
    }
  }
}
