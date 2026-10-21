import BoxmailCore

extension MailStore {
  func cachedMessageCount(accountId: String? = nil, folder: String? = nil) -> Int {
    messages.lazy.filter {
      (accountId == nil || $0.accountId == accountId) && (folder == nil || $0.folder == folder)
    }.count
  }
}
