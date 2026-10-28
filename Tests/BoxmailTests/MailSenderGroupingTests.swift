import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private func senderMail(
  _ id: String, address: String = "digest@example.test", account: String = "a",
  date: String = "2026-10-26T09:00:00Z"
) throws -> MailMessage {
  try JSONDecoder().decode(
    MailMessage.self,
    from: JSONSerialization.data(withJSONObject: [
      "id": id, "accountId": account, "folder": "inbox", "sender": "LINUX DO",
      "senderEmail": address,
      "to": "reader@example.test", "cc": "", "subject": "摘要 \(id)", "body": "正文", "preview": "社区更新",
      "date": date, "category": "未分类", "unread": false, "starred": false, "attachmentIds": [],
    ]))
}

private func senderGroup(_ message: MailMessage, count: Int = 3) -> MailSenderGroup {
  .init(
    id: "group-\(message.accountId)-\(message.senderEmail)", accountId: message.accountId,
    senderEmail: message.senderEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
    latestMessageId: message.id, count: count, unreadCount: 0)
}

private func senderPage(
  _ messages: [MailMessage], groups: [MailSenderGroup]? = nil,
  revealed: MailMessage? = nil, nextOffset: Int? = nil, total: Int? = nil
) throws -> MailPage {
  var value: [String: Any] = [
    "messages": try JSONSerialization.jsonObject(with: JSONEncoder().encode(messages)),
    "total": total ?? groups?.reduce(0) { $0 + $1.count } ?? messages.count,
  ]
  if let groups {
    value["senderGroups"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(groups))
    value["groupTotal"] = groups.count
  }
  if let revealed {
    value["revealedMessage"] = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(revealed))
  }
  if let nextOffset { value["nextOffset"] = nextOffset }
  return try JSONDecoder().decode(
    MailPage.self, from: JSONSerialization.data(withJSONObject: value))
}

@MainActor private func senderStore(backend: BackendService? = nil) -> MailStore {
  let store = MailStore(backend: backend)
  store.accountId = "a"
  store.groupMailBySender = true
  store.settings.preferences.markRead = false
  return store
}

@Suite(.serialized) @MainActor struct MailSenderGroupingTests {
  @Test func refreshingCollapsedGroupsDiscardsOldMembersAndPagination() throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old")
    let group = senderGroup(latest)
    let store = senderStore()
    let page = try senderPage([latest], groups: [group])
    store.applyMessagePage(page, reset: true, key: store.mailQueryKey, preserveSelection: false)
    store.senderGroupMessages[group.id] = [latest, old]
    store.senderGroupNextOffsets[group.id] = 100
    store.applyMessagePage(page, reset: true, key: store.mailQueryKey, preserveSelection: true)
    #expect(store.senderGroupMessages[group.id] == nil)
    #expect(store.senderGroupNextOffsets[group.id] == nil)
  }

  @Test func refreshingAGroupThatNowContainsOneMailRemovesHiddenSelectionsAndChildren() throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old")
    let group = senderGroup(latest)
    let store = senderStore()
    store.applyMessagePage(
      try senderPage([latest], groups: [group]), reset: true,
      key: store.mailQueryKey, preserveSelection: false)
    store.expandedSenderGroups = [group.id]
    store.senderGroupMessages[group.id] = [latest, old]
    store.setMailSelection([old.id], for: store.mailQueryKey)
    store.applyMessagePage(
      try senderPage([latest], groups: [senderGroup(latest, count: 1)]),
      reset: true, key: store.mailQueryKey, preserveSelection: true)
    #expect(store.expandedSenderGroups.isEmpty)
    #expect(store.filteredMessages.map(\.id) == [latest.id])
    #expect(store.selectedMessageIds == [latest.id])
  }

  @Test func senderGroupsStartCollapsedWithLatestMailAndFullCounts() throws {
    let newest = try senderMail("newest")
    let other = try senderMail("other", address: "other@example.test", date: "2026-10-25T00:00:00Z")
    let store = senderStore()
    store.applyMessagePage(
      try senderPage(
        [other, newest], groups: [senderGroup(other), senderGroup(newest, count: 250)]),
      reset: true, key: store.mailQueryKey, preserveSelection: false)
    #expect(store.filteredMessages.map(\.id) == ["newest", "other"])
    #expect(store.expandedSenderGroups.isEmpty)
    #expect(store.pageTotal == 253 && store.senderGroupTotal == 2)
    #expect(store.selectedMessageId == "newest")
    store.selectAllLoadedMail()
    #expect(store.selectedMessageIds == ["newest", "other"])
  }

  @Test func collapseNeverLeavesHiddenMailSelectedForBatchActions() throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old", date: "2026-10-20T00:00:00Z")
    let other = try senderMail("other", address: "other@example.test")
    let group = senderGroup(latest)
    let store = senderStore()
    store.applyMessagePage(
      try senderPage([latest, other], groups: [group, senderGroup(other, count: 1)]),
      reset: true, key: store.mailQueryKey, preserveSelection: false)
    store.senderGroupMessages[group.id] = [latest, old]
    store.toggleSenderGroup(group.id)
    store.setMailSelection([old.id], for: store.mailQueryKey)
    #expect(store.selectedMessageId == old.id)
    store.toggleSenderGroup(group.id)
    #expect(store.selectedMessageIds == [latest.id])
    #expect(store.selectedMessageId == latest.id)
    #expect(!store.filteredMessages.contains { $0.id == old.id })
    store.toggleSenderGroup(group.id)
    store.setMailSelection([old.id, other.id], for: store.mailQueryKey)
    store.toggleSenderGroup(group.id)
    #expect(store.selectedMessageIds == [other.id])
  }

  @Test func olderOriginalMailAutoExpandsItsSenderAndCanBeRevealed() throws {
    let latest = try senderMail("latest")
    let target = try senderMail("old-target", date: "2025-01-01T00:00:00Z")
    let group = senderGroup(latest, count: 400)
    let store = senderStore()
    store.messages = [latest, target]
    store.destination = .summary
    store.openMail(target, tab: .attachment)
    store.applyMessagePage(
      try senderPage([latest], groups: [group], revealed: target),
      reset: true, key: store.mailQueryKey, preserveSelection: false)
    #expect(store.expandedSenderGroups == [group.id])
    #expect(store.filteredMessages.map(\.id) == [latest.id, target.id])
    #expect(store.readyMailReveal?.messageId == target.id)
    #expect(store.selectedMails.map(\.id) == [target.id])
    #expect(store.mailAITab == .attachment)
  }

  @Test func parentPaginationKeepsExpandedChildrenAndDeduplicatesSenders() throws {
    let first = try senderMail("first")
    let old = try senderMail("old", date: "2026-09-01T00:00:00Z")
    let next = try senderMail("next", address: "next@example.test", date: "2026-10-25T00:00:00Z")
    let group = senderGroup(first)
    let store = senderStore()
    store.applyMessagePage(
      try senderPage([first], groups: [group], nextOffset: 1),
      reset: true, key: store.mailQueryKey, preserveSelection: false)
    store.senderGroupMessages[group.id] = [first, old]
    store.expandedSenderGroups = [group.id]
    store.applyMessagePage(
      try senderPage([first, next], groups: [group, senderGroup(next)]),
      reset: false, key: store.mailQueryKey, preserveSelection: false)
    #expect(store.filteredMessages.map(\.id) == [first.id, old.id, next.id])
    #expect(store.senderGroups.count == 2)
    #expect(store.expandedSenderGroups == [group.id])
  }

  @Test func switchingDisplayModeKeepsTheCurrentMailAsANavigationAnchor() throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old", date: "2026-09-01T00:00:00Z")
    let group = senderGroup(latest)
    let store = senderStore()
    store.messages = [latest, old]
    store.applyMessagePage(
      try senderPage([latest], groups: [group]), reset: true,
      key: store.mailQueryKey, preserveSelection: false)
    store.senderGroupMessages[group.id] = [latest, old]
    store.expandedSenderGroups = [group.id]
    store.setMailSelection([old.id], for: store.mailQueryKey)
    let previousKey = store.mailQueryKey
    store.changeSenderGrouping(false)
    #expect(store.mailQueryKey != previousKey)
    store.applyMessagePage(
      try senderPage([latest]), reset: true, key: store.mailQueryKey, preserveSelection: false)
    #expect(store.selectedMessageId == old.id)
    #expect(store.filteredMessages.contains { $0.id == old.id })
    #expect(!store.usesSenderGroups)
    store.setMailSelection([], for: previousKey)
    #expect(store.selectedMessageId == old.id)
  }

  @Test func memberLoadingKeepsFiltersAndEncodesTheOpaqueSenderId() async throws {
    let latest = try senderMail("latest", address: "a+b@example.test")
    let old = try senderMail("old", address: latest.senderEmail, date: "2026-09-01T00:00:00Z")
    let group = senderGroup(latest, count: 103)
    let stub = HTTPStub(
      path: "/messages",
      data: try JSONEncoder().encode(senderPage([latest, old], nextOffset: 100, total: 103)))
    defer { stub.close() }
    let store = senderStore(backend: BackendService(session: stub.session))
    store.search = "folder:archive 合同"
    store.filter = "未读"
    store.searchAllAccounts = true
    store.applyMessagePage(
      try senderPage([latest], groups: [group]), reset: true,
      key: store.mailQueryKey, preserveSelection: false)
    store.expandedSenderGroups = [group.id]
    await store.loadSenderGroup(group.id, reset: true)
    #expect(store.filteredMessages.map(\.id) == [latest.id, old.id])
    #expect(store.senderGroupNextOffsets[group.id] == 100)
    let url = try #require(stub.latestRequest?.url)
    #expect(url.absoluteString.contains("a%2Bb"))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first { $0.name == "senderGroup" }?.value == group.id)
    #expect(items.first { $0.name == "q" }?.value == store.search)
    #expect(items.first { $0.name == "filter" }?.value == "未读")
    #expect(items.first { $0.name == "accountId" }?.value == nil)
  }

  @Test func parentGroupingRequestsPreserveLiteralPlusInSearchConditions() async throws {
    let latest = try senderMail("latest", address: "a+b@example.test")
    let group = senderGroup(latest)
    let stub = HTTPStub(
      path: "/messages", data: try JSONEncoder().encode(senderPage([latest], groups: [group])))
    defer { stub.close() }
    let store = senderStore(backend: BackendService(session: stub.session))
    store.search = "from:a+b@example.test"
    await store.loadMessages(reset: true)
    let url = try #require(stub.latestRequest?.url)
    #expect(url.absoluteString.contains("a%2Bb"))
    #expect(store.filteredMessages.map(\.id) == [latest.id])
    #expect(store.usesSenderGroups)
  }

  @Test func memberRefreshRetainsAnExplicitlyRevealedOlderMailOutsideTheLoadedPage() async throws {
    let latest = try senderMail("latest")
    let target = try senderMail("old-target", date: "2020-01-01T00:00:00Z")
    let group = senderGroup(latest, count: 400)
    let stub = HTTPStub(
      path: "/messages",
      data: try JSONEncoder().encode(senderPage([latest], nextOffset: 100, total: 400)))
    defer { stub.close() }
    let store = senderStore(backend: BackendService(session: stub.session))
    store.messages = [latest, target]
    store.openMail(target)
    store.applyMessagePage(
      try senderPage([latest], groups: [group], revealed: target),
      reset: true, key: store.mailQueryKey, preserveSelection: false)
    await store.loadSenderGroup(group.id, reset: true)
    #expect(store.filteredMessages.map(\.id) == [latest.id, target.id])
    #expect(store.selectedMessageIds == [target.id])
  }

  @Test func memberFailurePreservesVisibleMailAndProvidesAnInlineRetryState() async throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old", date: "2026-09-01T00:00:00Z")
    let group = senderGroup(latest, count: 300)
    let stub = HTTPStub(path: "/messages", data: Data(#"{"error":"本机服务暂时不可用"}"#.utf8), status: 503)
    defer { stub.close() }
    let store = senderStore(backend: BackendService(session: stub.session))
    store.applyMessagePage(
      try senderPage([latest], groups: [group]), reset: true,
      key: store.mailQueryKey, preserveSelection: false)
    store.senderGroupMessages[group.id] = [latest, old]
    store.expandedSenderGroups = [group.id]
    store.senderGroupNextOffsets[group.id] = 100
    await store.loadSenderGroup(group.id, reset: false)
    #expect(store.filteredMessages.map(\.id) == [latest.id, old.id])
    #expect(store.senderGroupErrors[group.id] == "本机服务暂时不可用")
    #expect(store.senderGroupNextOffsets[group.id] == 100)
    #expect(store.senderGroupLoading.isEmpty && store.listError == nil)
  }

  @Test(arguments: [false, true])
  func oldMemberResponsesCannotPopulateAnotherQueryOrRestoredDatabase(restore: Bool) async throws {
    let latest = try senderMail("latest")
    let old = try senderMail("old")
    let group = senderGroup(latest)
    let stub = HTTPStub(
      path: "/messages", data: try JSONEncoder().encode(senderPage([latest, old])), delayed: true)
    defer { stub.close() }
    let store = senderStore(backend: BackendService(session: stub.session))
    store.applyMessagePage(
      try senderPage([latest], groups: [group]), reset: true,
      key: store.mailQueryKey, preserveSelection: false)
    let loading = Task { await store.loadSenderGroup(group.id, reset: true) }
    try await stub.waitUntilStarted()
    if restore { store.restoreRevision += 1 } else { store.accountId = "another-account" }
    stub.respond()
    await loading.value
    #expect(store.senderGroupMessages[group.id] == nil)
    #expect(store.senderGroupErrors.isEmpty)
    #expect(store.senderGroupLoading.isEmpty)
  }

  @Test func mailDateSortingAndSenderMembershipPreserveTimeAndAccountBoundaries() throws {
    let first = try senderMail("a", date: "2026-10-26T03:00:00-07:00")
    let tie = try senderMail("b", date: "2026-10-26T10:00:00Z")
    let old = try senderMail("c", date: "2026-10-26T11:00:00+02:00")
    #expect(MailMessage.sortedNewestFirst([old, tie, first]).map(\.id) == ["a", "b", "c"])
    let group = senderGroup(first)
    #expect(group.contains(try senderMail("case", address: " DIGEST@EXAMPLE.TEST ")))
    #expect(!group.contains(try senderMail("foreign", account: "b")))
    #expect(!group.contains(try senderMail("different", address: "alerts@example.test")))
  }
}
