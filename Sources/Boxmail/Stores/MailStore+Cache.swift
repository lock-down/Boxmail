import BoxmailCore

extension MailStore {
  var retainedAttachmentIds: Set<String> {
    Set(
      (selectedMessage?.attachmentIds ?? [])
        + (conversationAnchor == selectedMessageId
          ? conversationBodies.values.flatMap(\.attachmentIds) : [])
        + [previewAttachment?.id].compactMap { $0 })
  }

  func cacheAttachment(_ attachment: MailAttachment) {
    guard retainedAttachmentIds.contains(attachment.id) else { return }
    attachmentCache[attachment.id] = attachment
    if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
      attachments[index] = attachment
    }
  }

  func trimAttachmentCache(keeping ids: [String]) {
    let kept = Set(ids + [previewAttachment?.id].compactMap { $0 })
    attachmentCache = attachmentCache.filter { kept.contains($0.key) }
    attachments = attachments.map { kept.contains($0.id) ? $0 : $0.compact }
  }

  func unloadConversationBody(_ id: String) {
    conversationBodyRequests[id] = nil
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
