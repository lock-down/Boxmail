import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private func loadingMessage(_ id: String, attachments: [String] = []) throws -> MailMessage {
  try JSONDecoder().decode(
    MailMessage.self,
    from: JSONSerialization.data(withJSONObject: [
      "id": id, "accountId": "account", "folder": "inbox", "sender": "Sender",
      "senderEmail": "sender@example.test", "to": "reader@example.test", "cc": "",
      "subject": "Mail", "body": "Body", "preview": "Preview", "date": "2026-10-25T00:00:00Z",
      "category": "未分类", "unread": false, "starred": false, "attachmentIds": attachments,
    ]))
}

private func loadingAttachment(_ id: String, messageId: String) throws -> MailAttachment {
  try JSONDecoder().decode(
    MailAttachment.self,
    from: JSONSerialization.data(withJSONObject: [
      "id": id, "messageId": messageId, "name": "file.txt", "contentType": "text/plain",
      "path": "/synthetic/file.txt", "text": String(repeating: "Extracted content", count: 100),
      "analysis": "Saved analysis", "parseError": "", "date": "2026-10-25T00:00:00Z", "size": 100,
    ]))
}

@Test(arguments: [false, true])
@MainActor func lateAttachmentResponsesKeepOnlyVisibleContent(previewOpen: Bool) async throws {
  let id = UUID().uuidString
  let first = try loadingMessage("first", attachments: [id])
  let second = try loadingMessage("second")
  let attachment = try loadingAttachment(id, messageId: first.id)
  let stub = HTTPStub(
    path: "/attachments/\(id)/metadata", data: try JSONEncoder().encode(attachment), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.messages = [first, second]
  store.attachments = [attachment.compact]
  store.selectedMessageId = first.id
  if previewOpen { store.previewAttachment = attachment.compact }
  let loading = Task { await store.loadAttachment(id) }
  try await stub.waitUntilStarted()
  store.selectedMessageId = second.id
  stub.respond()
  await loading.value
  #expect((store.attachmentCache[id] != nil) == previewOpen)
  #expect(store.attachments[0].text.isEmpty != previewOpen)
  #expect(store.mailAIErrors.isEmpty)
}

@Test @MainActor func lateAttachmentFailuresDoNotReportErrorsOnAnotherMail() async throws {
  let id = UUID().uuidString
  let stub = HTTPStub(
    path: "/attachments/\(id)/metadata", data: Data(#"{"error":"old failure"}"#.utf8), status: 500,
    delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.messages = try [loadingMessage("first", attachments: [id]), loadingMessage("second")]
  store.selectedMessageId = "first"
  let loading = Task { await store.loadAttachment(id) }
  try await stub.waitUntilStarted()
  store.selectedMessageId = "second"
  stub.respond()
  await loading.value
  #expect(store.mailAIErrors.isEmpty)
}

@Test @MainActor func restoringDataDiscardsAttachmentResponsesFromThePreviousDatabase() async throws
{
  let id = UUID().uuidString
  let message = try loadingMessage("mail", attachments: [id])
  let attachment = try loadingAttachment(id, messageId: message.id)
  let stub = HTTPStub(
    path: "/attachments/\(id)/metadata", data: try JSONEncoder().encode(attachment), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.messages = [message]
  store.selectedMessageId = message.id
  let loading = Task { await store.loadAttachment(id) }
  try await stub.waitUntilStarted()
  store.restoreRevision += 1
  stub.respond()
  await loading.value
  #expect(store.attachmentCache.isEmpty)
}

@Test(arguments: [false, true])
@MainActor func collapsedOrReplacedConversationDoesNotReopenAfterAnOldResponse(navigate: Bool)
  async throws
{
  let id = UUID().uuidString
  let anchor = try loadingMessage("anchor")
  let full = try loadingMessage(id)
  let stub = HTTPStub(path: "/messages/\(id)", data: try JSONEncoder().encode(full), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.messages = [anchor, full]
  store.selectedMessageId = anchor.id
  store.conversationAnchor = anchor.id
  store.conversation = try JSONDecoder().decode(
    MailConversation.self,
    from: JSONSerialization.data(withJSONObject: [
      "id": "thread", "accountId": "account",
      "messages": try JSONSerialization.jsonObject(with: JSONEncoder().encode([anchor, full])),
      "total": 2, "partial": false,
    ]))
  let loading = Task { await store.loadConversationBody(full) }
  try await stub.waitUntilStarted()
  if navigate { store.detailGeneration = UUID() } else { store.unloadConversationBody(id) }
  stub.respond()
  await loading.value
  #expect(store.conversationBodies[id] == nil)
  #expect(store.conversationBodyRequests.isEmpty)
  #expect(store.conversationError == nil)
}

@Test @MainActor func obsoleteMetadataCannotOverwriteANewerRefreshOrRestoredData() async throws {
  func snapshot(_ id: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "accounts": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode([
          MailAccount(id: id, email: "\(id)@example.test", isDemo: true)
        ])),
      "messages": [], "drafts": [], "attachments": [], "jobs": [], "events": [],
      "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(SettingsData())),
      "pendingMutations": 0,
    ])
  }
  for restore in [false, true] {
    let older = HTTPStub(path: "/state", data: try snapshot("older"), delayed: true)
    let page = HTTPStub(path: "/messages", data: Data(#"{"messages":[],"total":0}"#.utf8))
    defer {
      older.close()
      page.close()
    }
    let store = MailStore(backend: BackendService(session: older.session))
    let loading = Task { try await store.refresh(reloadContent: false) }
    try await older.waitUntilStarted()
    if restore {
      store.restoreRevision += 1
      store.accounts = [MailAccount(id: "newer", email: "newer@example.test", isDemo: true)]
    } else {
      let newer = HTTPStub(path: "/state", data: try snapshot("newer"))
      defer { newer.close() }
      try await store.refresh(reloadContent: false)
    }
    older.respond()
    try await loading.value
    #expect(store.accounts.map(\.id) == ["newer"])
  }
}
