import Foundation
import BoxmailCore

struct MailSourceContext {
  let accountId: String
  let destination: MailDestination
  var query: MailQuery? = nil
  var savedSearchID: String? = nil
  var mailList: MailListNavigationState? = nil
  var returnTitle: String { destination == .organize ? "返回分类结果" : "返回\(destination.title)" }
}

struct MailListNavigationState {
  let key: String
  let messages: [MailMessage]
  let selectedId: String?
  let selectedIds: Set<String>
  let total: Int
  let nextOffset: Int?
  let categoryCounts: [String: Int]
  let unreadCount: Int
  let senderGroups: [MailSenderGroup]
  let groupTotal: Int
  let expandedGroups: Set<String>
  let groupMessages: [String: [MailMessage]]
  let groupOffsets: [String: Int]
  let senderGroupsLoaded: Bool
}

struct MailRevealRequest: Equatable {
  let id = UUID()
  let messageId: String
  let queryKey: String
}

extension MailStore {
  func organizationWorkspace() -> OrganizationWorkspaceState {
    if let state = organizationWorkspaces[accountId] { return state }
    let state = OrganizationWorkspaceState(backend: backend, accountId: accountId)
    organizationWorkspaces[accountId] = state
    return state
  }

  func returnToMailSource() {
    guard let source = mailSource else { return }
    let previousKey = mailQueryKey
    mailSource = nil
    accountId = source.accountId
    navigate(source.destination)
    if let query = source.query {
      unifiedInbox = query.accountId == nil
      searchAllAccounts = query.accountId == nil
      search = query.query; filter = query.filter; listCategory = query.category ?? ""
      activeSavedSearchId = source.savedSearchID
    }
    if let state = source.mailList, state.key == mailQueryKey {
      pageMessages = state.messages; pageTotal = state.total; nextOffset = state.nextOffset
      listCategoryCounts = state.categoryCounts; listUnreadCount = state.unreadCount
      clearSenderGroups()
      senderGroups = state.senderGroups; senderGroupTotal = state.groupTotal
      expandedSenderGroups = state.expandedGroups; senderGroupMessages = state.groupMessages
      senderGroupNextOffsets = state.groupOffsets
      senderGroupsLoaded = state.senderGroupsLoaded
      pageKey = mailQueryKey; selectionQueryKey = mailQueryKey
      selectedMessageId = state.selectedId; selectedMessageIds = state.selectedIds
      if previousKey != mailQueryKey { restoredMailQueryKey = mailQueryKey }
      if let id = state.selectedId { mailRevealRequest = .init(messageId: id, queryKey: mailQueryKey) }
    }
    mailListFocusRequest += 1
  }

  func captureSourceContext() -> MailSourceContext {
    let query = isMailWorkspace ? mailQuery : nil
    let snapshot: MailListNavigationState? = query != nil && pageKey == mailQueryKey
      ? .init(key: pageKey, messages: pageMessages,
      selectedId: selectedMessageId, selectedIds: selectedMessageIds, total: pageTotal, nextOffset: nextOffset,
      categoryCounts: listCategoryCounts, unreadCount: listUnreadCount,
      senderGroups: senderGroups, groupTotal: senderGroupTotal, expandedGroups: expandedSenderGroups,
      groupMessages: senderGroupMessages, groupOffsets: senderGroupNextOffsets,
      senderGroupsLoaded: senderGroupsLoaded) : nil
    return .init(accountId: accountId, destination: destination, query: query,
      savedSearchID: activeSavedSearchId, mailList: snapshot)
  }

  var readyMailReveal: MailRevealRequest? {
    guard let request = mailRevealRequest, request.queryKey == mailQueryKey,
      selectedMessageId == request.messageId, selectedMessageIds == [request.messageId],
      filteredMessages.contains(where: { $0.id == request.messageId }) else { return nil }
    return request
  }

  func finishMailReveal(_ request: MailRevealRequest) {
    if mailRevealRequest == request { mailRevealRequest = nil }
  }
}
