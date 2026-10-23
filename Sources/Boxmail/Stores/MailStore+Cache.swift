import BoxmailCore

extension MailStore {
  func trimAttachmentCache(keeping ids: [String]) {
    let kept = Set(ids + [previewAttachment?.id].compactMap { $0 })
    attachmentCache = attachmentCache.filter { kept.contains($0.key) }
    attachments = attachments.map { kept.contains($0.id) ? $0 : $0.compact }
  }

  func unloadConversationBody(_ id: String) {
    conversationBodies[id] = nil
    trimAttachmentCache(keeping: (selectedMessage?.attachmentIds ?? [])
      + conversationBodies.values.flatMap(\.attachmentIds))
  }

  func cachedMessageCount(accountId: String? = nil, folder: String? = nil) -> Int {
    messages.lazy.filter {
      (accountId == nil || $0.accountId == accountId) && (folder == nil || $0.folder == folder)
    }.count
  }
}
