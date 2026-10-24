import BoxmailCore
import Foundation
import Testing
@testable import Boxmail

private func message(_ id: String, account: String = "account", folder: String = "inbox") throws -> MailMessage {
  let json: [String: Any] = [
    "id": id, "accountId": account, "folder": folder, "sender": "测试发件人",
    "senderEmail": "sender@example.test", "to": "reader@example.test", "cc": "",
    "subject": "邮件 \(id)", "body": "正文 \(id)", "preview": "预览 \(id)",
    "date": "2026-10-24T08:00:00Z", "category": "", "unread": false,
    "starred": false, "attachmentIds": [],
  ]
  return try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: json))
}

private func page(_ messages: [MailMessage], total: Int? = nil, nextOffset: Int? = nil) throws -> MailPage {
  var json: [String: Any] = [
    "messages": try JSONSerialization.jsonObject(with: JSONEncoder().encode(messages)),
    "total": total ?? messages.count,
  ]
  if let nextOffset { json["nextOffset"] = nextOffset }
  return try JSONDecoder().decode(MailPage.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test(arguments: [MailDestination.summary, .attachments, .organize])
@MainActor func openingOriginalMailKeepsTargetWhileDestinationLoads(source: MailDestination) throws {
  let store = MailStore()
  store.accountId = "account"
  store.destination = source
  store.pageKey = store.mailQueryKey
  store.selectionQueryKey = store.mailQueryKey
  let first = try message("first")
  let target = try message("target")
  store.messages = [first, target]

  store.openMail(target, tab: .attachment)
  // The new list appears before its asynchronous request has returned.
  store.reconcileMailSelection()
  store.applyMailSelection()

  #expect(store.destination == .inbox)
  #expect(store.selectedMessageId == target.id)
  #expect(store.selectedMessageIds == [target.id])
  #expect(store.mailAITab == .attachment)
}

@Test(arguments: ["inbox", "sent", "archive", "trash"])
@MainActor func originalMailNavigationLoadsTheRightAccountFolderAndPanel(folder: String) throws {
  let store = MailStore()
  store.accountId = "previous-account"
  store.destination = .summary
  store.search = "旧查询"
  store.filter = "未读"
  store.pageKey = store.mailQueryKey
  let oldKey = store.mailQueryKey
  let first = try message("first", account: "other-account", folder: folder)
  let target = try message("target", account: "other-account", folder: folder)
  store.messages = [first, target]

  store.openMail(target, tab: .summary)
  store.setMailSelection([], for: oldKey)
  store.reconcileMailSelection()
  store.applyMessagePage(try page([first, target]), reset: true, key: store.mailQueryKey, preserveSelection: false)

  #expect(store.accountId == target.accountId)
  #expect(store.destination.rawValue == folder)
  #expect(store.search.isEmpty && store.filter == "全部")
  #expect(store.selectedMessage?.id == target.id)
  #expect(store.selectedMails.map(\.id) == [target.id])
  #expect(store.mailAITab == .summary)
}

@Test @MainActor func originalMailBeyondFirstPageStaysVisibleThroughPaginationAndRefresh() throws {
  let store = MailStore()
  store.accountId = "account"
  store.destination = .attachments
  store.pageKey = store.mailQueryKey
  let first = try message("first")
  let target = try message("older-than-first-page")
  store.messages = [first, target]
  store.openMail(target, tab: .attachment)
  let key = store.mailQueryKey

  store.applyMessagePage(try page([first], total: 101, nextOffset: 100), reset: true, key: key, preserveSelection: false)
  #expect(store.filteredMessages.map(\.id) == [target.id, first.id])
  #expect(store.selectedMessageId == target.id && store.mailAITab == .attachment)
  store.applyMessagePage(try page([target], total: 101), reset: false, key: key, preserveSelection: false)
  #expect(store.filteredMessages.filter { $0.id == target.id }.count == 1)
  #expect(store.selectedMessageId == target.id && store.mailAITab == .attachment)
  store.applyMessagePage(try page([first], total: 101, nextOffset: 100), reset: true, key: key, preserveSelection: true)
  #expect(store.selectedMessageId == target.id && store.selectedMessageIds == [target.id])
}

@Test @MainActor func pageResponseKeepsMailOpenedAfterRequestStartedAndRejectsOldQueryCallbacks() throws {
  let store = MailStore()
  store.accountId = "account"
  let inboxKey = store.mailQueryKey
  let first = try message("first")
  let target = try message("target")
  let archived = try message("archived", folder: "archive")
  store.messages = [first, target, archived]

  store.openMail(target, tab: .reply)
  store.applyMessagePage(try page([first, target]), reset: true, key: inboxKey, preserveSelection: false)
  #expect(store.selectedMessageId == target.id && store.mailAITab == .reply)

  store.openMail(archived, tab: .summary)
  store.setMailSelection([first.id], for: inboxKey)
  store.applyMessagePage(try page([first]), reset: true, key: inboxKey, preserveSelection: false)
  #expect(store.selectedMessageId == archived.id && store.mailAITab == .summary)
  store.applyMessagePage(try page([archived]), reset: true, key: store.mailQueryKey, preserveSelection: false)
  store.setMailSelection([], for: inboxKey)
  #expect(store.selectedMessageId == archived.id && store.selectedMessageIds == [archived.id])
}

@Test @MainActor func nativeSingleMultiAndSelectAllStayConsistentWithDetail() throws {
  let store = MailStore()
  store.accountId = "account"
  let mails = try [message("first"), message("second"), message("third")]
  store.messages = mails
  let key = store.mailQueryKey
  store.applyMessagePage(try page(mails), reset: true, key: key, preserveSelection: false)
  store.setMailSelection(["second"], for: key)
  #expect(store.selectedMessageId == "second")
  store.setMailSelection(["second", "third"], for: key)
  #expect(store.selectedMessageId == "second" && store.selectedMails.count == 2)
  store.selectAllLoadedMail()
  #expect(store.selectedMails.count == 3 && store.selectedMessageIds.contains(store.selectedMessageId ?? ""))
  store.clearMailSelection()
  #expect(store.selectedMessageId == nil && store.selectedMessageIds.isEmpty)
  store.setMailSelection(["third"], for: key)
  #expect(store.selectedMessageId == "third" && store.selectedMessageIds == ["third"])
}

@Test @MainActor func refreshRetainsRemainingMultiSelectionWithoutReopeningOtherMail() throws {
  let store = MailStore()
  store.accountId = "account"
  let mails = try [message("first"), message("second"), message("third")]
  store.messages = mails
  let key = store.mailQueryKey
  store.applyMessagePage(try page(mails), reset: true, key: key, preserveSelection: false)
  store.setMailSelection(["second", "third"], for: key)
  store.messages.removeAll { $0.id == "second" }
  store.applyMessagePage(try page([mails[0], mails[2]]), reset: true, key: key, preserveSelection: true)
  #expect(store.selectedMessageId == "third" && store.selectedMessageIds == ["third"])
  store.messages = []
  store.applyMessagePage(try page([]), reset: true, key: key, preserveSelection: true)
  #expect(store.selectedMessageId == nil && store.selectedMessageIds.isEmpty)
}

@Test @MainActor func changingSearchFilterOrAccountDiscardsPreviousMultiSelection() throws {
  let store = MailStore()
  store.accountId = "account"
  let first = try message("first")
  let target = try message("target", account: "other-account")
  store.messages = [first, target]
  let oldKey = store.mailQueryKey
  store.applyMessagePage(try page([first]), reset: true, key: oldKey, preserveSelection: false)
  store.accountId = target.accountId
  store.search = "正文"
  store.filter = "有附件"
  store.applyMessagePage(try page([target]), reset: true, key: store.mailQueryKey, preserveSelection: false)
  #expect(store.selectedMessageId == target.id && store.selectedMessageIds == [target.id])
  store.setMailSelection([first.id], for: oldKey)
  #expect(store.selectedMessageId == target.id && store.selectedMessageIds == [target.id])
}

@Test @MainActor func searchDraftsCanOpenSinglyButStayOutOfBulkMailActions() throws {
  let store = MailStore()
  store.accountId = "account"
  store.search = "草稿"
  let mail = try message("mail")
  var draft = try message("draft:one")
  draft.draftId = "one"
  store.messages = [mail]
  store.applyMessagePage(try page([mail, draft]), reset: true, key: store.mailQueryKey, preserveSelection: false)
  store.setMailSelection([draft.id], for: store.mailQueryKey)
  #expect(store.selectedMessage?.draftId == "one" && store.selectedMails.isEmpty)
  store.setMailSelection([mail.id, draft.id], for: store.mailQueryKey)
  #expect(store.selectedMessageId == mail.id && store.selectedMessageIds == [mail.id])
  store.selectAllLoadedMail()
  #expect(store.selectedMessageIds == [mail.id])
  store.ready = true
  store.setMailSelection([draft.id], for: store.mailQueryKey)
  #expect(store.selectedMailForCommands == nil)
}

@Test @MainActor func messageCommandsRequireASingleVisibleMailAndNoComposerOrSettings() throws {
  let store = MailStore()
  store.accountId = "account"
  let mails = try [message("first"), message("second")]
  store.messages = mails
  let key = store.mailQueryKey
  store.applyMessagePage(try page(mails), reset: true, key: key, preserveSelection: false)
  #expect(store.selectedMailForCommands == nil)
  store.ready = true
  #expect(store.selectedMailForCommands?.id == "first")
  store.setMailSelection(["first", "second"], for: key)
  #expect(store.selectedMailForCommands == nil)
  store.setMailSelection(["second"], for: key)
  #expect(store.selectedMailForCommands?.id == "second")
  store.composer = MailDraft(accountId: "account")
  #expect(store.selectedMailForCommands == nil)
  store.composer = nil
  store.showSettings = true
  #expect(store.selectedMailForCommands == nil)
  store.showSettings = false
  store.navigate(.summary)
  #expect(store.selectedMailForCommands == nil)
}

@Test @MainActor func composeWithoutAnAccountOpensSetupInsteadOfAnUnsavableDraft() {
  let store = MailStore()
  store.ready = true
  store.newDraft()
  #expect(store.composer == nil)
  #expect(store.showSettings && store.settingsTab == "账号")
  store.showSettings = false
  let account = MailAccount(id: "account", email: "reader@example.test", isDemo: true)
  store.accounts = [account]
  store.accountId = account.id
  store.newDraft()
  #expect(store.composer?.accountId == account.id)
  #expect(!store.showSettings)
}
