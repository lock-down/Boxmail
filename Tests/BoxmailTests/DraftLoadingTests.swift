import BoxmailCore
import Foundation
import Testing
@testable import Boxmail

private func fullDraft() -> MailDraft {
  var draft = MailDraft(accountId: "account", body: "Editable introduction")
  draft.subject = "Saved forward"
  draft.preview = "Editable introduction Original forwarded content"
  draft.forwardedText = "Original forwarded content"
  draft.forwardedHTML = "<p>Original forwarded content</p>"
  draft.bodyLoaded = true
  return draft
}

@MainActor private func finishDraftLoading(_ store: MailStore) async throws {
  for _ in 0..<500 {
    if !store.busy.contains("draft-load") { return }
    try await Task.sleep(for: .milliseconds(2))
  }
  throw URLError(.timedOut)
}

@MainActor @Test func lightDraftsLoadTheirCompleteEditableContentBeforeOpeningTheComposer() async throws {
  let full = fullDraft()
  let stub = HTTPStub(path: "/drafts/\(full.id)", data: try JSONEncoder().encode(full), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.drafts = [full.compact]
  store.editDraft(full.id)
  try await stub.waitUntilStarted()
  #expect(store.composer == nil)
  #expect(store.drafts[0].body.isEmpty && store.drafts[0].forwardedText == nil)
  stub.respond()
  try await finishDraftLoading(store)
  #expect(store.composer == full)
  #expect(store.drafts[0].bodyLoaded == false && store.drafts[0].body.isEmpty)
}

@MainActor @Test(arguments: ["restore", "removed", "new-composer"])
func staleDraftResponsesCannotOpenOrReplaceUnrelatedWork(change: String) async throws {
  let full = fullDraft()
  let stub = HTTPStub(path: "/drafts/\(full.id)", data: try JSONEncoder().encode(full), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.drafts = [full.compact]
  store.editDraft(full.id)
  try await stub.waitUntilStarted()
  if change == "restore" { store.restoreRevision += 1 }
  if change == "removed" { store.drafts = [] }
  let other = MailDraft(accountId: "account", body: "Unrelated new work")
  if change == "new-composer" { store.composer = other }
  stub.respond()
  try await finishDraftLoading(store)
  #expect(store.composer == (change == "new-composer" ? other : nil))
}

@MainActor @Test func failedDraftLoadingDoesNotExposeAnEmptyEditableCopy() async throws {
  let full = fullDraft()
  let stub = HTTPStub(path: "/drafts/\(full.id)", data: Data(#"{"error":"Synthetic failure"}"#.utf8), status: 502)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.drafts = [full.compact]
  store.editDraft(full.id)
  try await finishDraftLoading(store)
  #expect(store.composer == nil)
  #expect(store.error?.contains("原草稿已保留") == true)
  #expect(store.drafts == [full.compact])
}

@MainActor @Test func newAndSavedDraftRequestsCannotReplaceAnOpenComposer() {
  let store = MailStore()
  store.accounts = [MailAccount(id: "account", email: "me@example.test")]
  store.accountId = "account"
  let open = MailDraft(accountId: "account", body: "Unsaved current work")
  let other = fullDraft()
  store.drafts = [other]
  store.composer = open
  store.newDraft()
  #expect(store.composer == open)
  store.editDraft(other.id)
  #expect(store.composer == open)
}

@MainActor @Test(arguments: ["new-draft", "restored", "settings"])
func lateReplyDraftCannotReplaceNewWorkOrReopenAfterRestore(change: String) async throws {
  let message = try JSONDecoder().decode(
    MailMessage.self,
    from: Data(
      #"{"id":"message","accountId":"account","folder":"inbox","sender":"Sender","senderEmail":"sender@example.test","to":"me@example.test","cc":"","subject":"Original","body":"Body","preview":"Body","date":"2026-11-02T01:00:00Z","category":"","unread":false,"starred":false,"attachmentIds":[]}"#
        .utf8))
  let reply = fullDraft()
  let stub = HTTPStub(
    path: "/messages/message/reply-draft", data: try JSONEncoder().encode(reply), delayed: true)
  defer { stub.close() }
  let store = MailStore(backend: BackendService(session: stub.session))
  store.accounts = [MailAccount(id: "account", email: "me@example.test")]
  store.accountId = "account"
  store.newDraft(reply: message)
  try await stub.waitUntilStarted()
  if change == "new-draft" { store.newDraft() }
  if change == "restored" { store.restoreRevision += 1 }
  if change == "settings" { store.showSettings = true }
  let expected = store.composer
  stub.respond()
  for _ in 0..<500 {
    if !store.busy.contains("compose-reply") { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(!store.busy.contains("compose-reply"))
  #expect(store.composer == expected)
}
