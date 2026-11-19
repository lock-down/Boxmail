import BoxmailCore
import Foundation

@MainActor enum AssistantPresentation {
  static func actionTitle(_ action: AssistantAction) -> String {
    switch action.kind {
    case "category": return "将 \(action.messageIds.count) 封邮件分类为\(action.category ?? "")"
    case "draft": return "为 \(action.messageIds.count) 封邮件创建回复草稿"
    default: return "收录 \(action.messageIds.count) 个跟进：\(action.title ?? "")"
    }
  }

  static func scopeTitle(_ scope: AssistantScope, store: MailStore) -> String {
    if scope.kind == "folder", let folder = scope.query?.folder {
      return MailDestination.title(forFolder: folder) ?? folder
    }
    if scope.kind == "search", let query = scope.query {
      let account = query.accountId.flatMap { id in store.accounts.first { $0.id == id }?.email } ?? "所有账户"
      let folder = MailDestination.title(forFolder: query.folder) ?? query.folder
      return [account, folder, query.filter == "全部" ? nil : query.filter, query.category,
        query.query.isEmpty ? nil : query.query].compactMap { $0 }.joined(separator: " · ")
    }
    if scope.kind == "attachments" {
      return "\(scope.attachmentIds?.count ?? 0) 个所选附件"
    }
    return
      "\(scope.kind == "conversation" ? "当前会话" : "当前邮件") · \(store.messages.first { $0.id == scope.messageId }?.subject ?? "来源邮件")"
  }

  static func scopeHelp(_ scope: AssistantScope, store: MailStore) -> String {
    let title = scopeTitle(scope, store: store)
    guard scope.kind == "folder", let query = scope.query else { return title }
    let account = query.accountId.flatMap { id in store.accounts.first { $0.id == id }?.email }
    return "\(title) · \(account ?? "所有账户")"
  }
}
