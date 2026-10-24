import BoxmailCore
import Foundation
import Testing
@testable import Boxmail

private func snapshot(_ folders: [[String: Any]]) throws -> MailSyncSnapshot {
  try JSONDecoder().decode(MailSyncSnapshot.self, from: JSONSerialization.data(withJSONObject: [
    "runningAccounts": ["a", "b"], "folders": folders, "results": [],
  ]))
}

@Test @MainActor func syncProgressCountsOnlyAccountsInThisSession() throws {
  let store = MailStore()
  store.syncingAccountIds = ["a", "b"]
  store.syncSnapshot = try snapshot([
    ["id": "a-in", "accountId": "a", "folder": "inbox", "status": "partial", "downloaded": 200, "total": 1005],
    ["id": "b-in", "accountId": "b", "folder": "inbox", "status": "completed", "downloaded": 20, "total": 20],
    ["id": "other", "accountId": "other", "folder": "inbox", "status": "partial", "downloaded": 499, "total": 500],
  ])
  #expect(store.syncProgressText == "正在同步 220/1025 封")
}

@Test @MainActor func folderSyncProgressExcludesOtherFolderCheckpoints() throws {
  let store = MailStore()
  store.syncingAccountIds = ["a"]
  store.syncingFolder = "inbox"
  store.syncSnapshot = try snapshot([
    ["id": "in", "accountId": "a", "folder": "inbox", "status": "running", "downloaded": 200, "total": 405],
    ["id": "sent", "accountId": "a", "folder": "sent", "status": "partial", "downloaded": 10, "total": 100],
  ])
  #expect(store.syncProgressText == "正在同步 200/405 封")
}

@Test @MainActor func syncProgressShowsDiscoveryAndStoppingWithoutClaimingCompletion() {
  let store = MailStore()
  #expect(store.syncProgressText == "正在同步…")
  store.syncCancellationRequested = true
  #expect(store.syncProgressText == "正在停止同步…")
}
