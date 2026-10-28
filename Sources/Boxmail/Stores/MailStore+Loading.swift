import AppKit
import BoxmailCore
import Network

extension MailStore {
  var mailQueryKey: String {
    [accountId, destination.rawValue, filter, search, String(searchAllAccounts), String(groupMailBySender)]
      .joined(separator: "\u{1f}")
  }
  var currentSyncFolder: MailSyncFolder? {
    syncSnapshot?.folders.first { $0.accountId == accountId && $0.folder == destination.rawValue }
  }

  func loadMessages(reset: Bool, preserveSelection: Bool = false) async {
    let key = mailQueryKey
    if !reset && (listLoading || nextOffset == nil || pageKey != key) { return }
    let generation = UUID()
    pageGeneration = generation
    listLoading = true
    listError = nil
    if reset && pageKey != key { pageTotal = 0; nextOffset = nil }
    defer { if pageGeneration == generation { listLoading = false } }
    var query = URLComponents()
    query.queryItems = [
      URLQueryItem(name: "accountId", value: !search.isEmpty && searchAllAccounts ? nil : accountId),
      URLQueryItem(name: "folder", value: destination.rawValue),
      URLQueryItem(name: "q", value: search),
      URLQueryItem(name: "filter", value: filter),
      URLQueryItem(
        name: "limit",
        value: String(reset && preserveSelection ? min(200, max(100, pageMessages.count)) : 100)),
      URLQueryItem(name: "offset", value: String(reset ? 0 : nextOffset ?? 0)),
    ]
    if groupMailBySender {
      query.queryItems?.append(URLQueryItem(name: "groupBy", value: "sender"))
      if reset, preserveSelection || pinnedQueryKey == key {
        query.queryItems?.append(URLQueryItem(name: "revealId", value: selectedMessageId))
      }
    }
    let encodedQuery = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
    do {
      let page: MailPage = try await self.backend.request(
        "/messages?\(encodedQuery)")
      try Task.checkCancellation()
      guard pageGeneration == generation, key == mailQueryKey else { return }
      applyMessagePage(page, reset: reset, key: key, preserveSelection: preserveSelection)
      if reset, page.senderGroups != nil {
        await withTaskGroup(of: Void.self) { tasks in
          for group in senderGroups where expandedSenderGroups.contains(group.id) {
            tasks.addTask { @MainActor in await self.loadSenderGroup(group.id, reset: true) }
          }
        }
      }
    } catch is CancellationError {
    } catch {
      guard pageGeneration == generation else { return }
      listError = error.localizedDescription
    }
  }

  func applyMessagePage(_ page: MailPage, reset: Bool, key: String, preserveSelection: Bool) {
    guard key == mailQueryKey else { return }
    if page.senderGroups != nil {
      applySenderGroupPage(page, reset: reset, key: key, preserveSelection: preserveSelection)
      return
    }
    if reset { clearSenderGroups() }
    let selectionWasInQuery =
      pageKey == key
      && selectedMessageId.map { id in filteredMessages.contains { $0.id == id } } == true
    // Read the current selection when the response arrives; another entry point
    // may have opened a different mail while this request was in flight.
    let keepSelection =
      (preserveSelection && pageKey == key)
      || (pinnedQueryKey == key && pinnedMessageId == selectedMessageId)
    if reset {
      pageMessages = page.messages
    } else {
      let ids = Set(pageMessages.map(\.id))
      pageMessages += page.messages.filter { !ids.contains($0.id) }
    }
    pageKey = key
    pageTotal = page.total
    nextOffset = page.nextOffset
    if reset && !keepSelection { selectedMessageId = pageMessages.first?.id }
    if let id = selectedMessageId, !pageMessages.contains(where: { $0.id == id }),
      keepSelection, let header = messages.first(where: { $0.id == id }),
      header.accountId == accountId,
      search.isEmpty || selectionWasInQuery || pinnedQueryKey == key,
      !search.isEmpty
        || (destination == .starred
          ? header.starred && header.folder != "trash"
          : destination == .summary
            ? header.summary != nil && header.folder != "trash"
            : header.folder == destination.rawValue),
      filter != "未读" || header.unread,
      filter != "有附件" || !header.attachmentIds.isEmpty,
      filter != "AI 已总结" || header.summary != nil
    {
      pinnedMessageId = id
      pinnedQueryKey = key
    } else if reset, let id = selectedMessageId, !pageMessages.contains(where: { $0.id == id }) {
      pinnedMessageId = nil
      selectedMessageId = pageMessages.first?.id
    }
    reconcileMailSelection()
  }

  func loadSelectedMessage() async {
    guard let id = selectedMessageId else { return }
    let generation = UUID()
    detailGeneration = generation
    detailError = nil
    do {
      let full: MailMessage = try await self.backend.request("/messages/\(id)")
      try Task.checkCancellation()
      guard id == selectedMessageId, generation == detailGeneration else { return }
      // Keep only the selected body; headers and summaries remain available for overview screens.
      detailCache = [id: full]
      trimAttachmentCache(keeping: full.attachmentIds)
      for aid in full.attachmentIds { await loadAttachment(aid) }
      guard id == selectedMessageId, generation == detailGeneration else { return }
      if full.draftId != nil {
        conversation = nil; conversationAnchor = nil; conversationError = nil
        return
      }
      await loadConversation()
    } catch is CancellationError {
    } catch {
      if selectedMessageId == id && generation == detailGeneration {
        detailError = error.localizedDescription
      }
    }
  }

  func loadAttachment(_ id: String) async {
    guard !Task.isCancelled else { return }
    let revision = restoreRevision
    do {
      let full: MailAttachment = try await self.backend.request(
        "/attachments/\(id)/metadata")
      try Task.checkCancellation()
      guard revision == restoreRevision else { return }
      cacheAttachment(full)
    } catch is CancellationError {
    } catch {
      if revision == restoreRevision, retainedAttachmentIds.contains(id), let selectedMessageId {
        mailAIErrors[selectedMessageId] = "附件内容加载失败，可重新打开邮件重试。"
      }
    }
  }

  func startSyncMonitoring() {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(2))
        await self?.syncAll(silent: true)
      }
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let available = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let self else { return }
        let restored = self.lastNetworkSatisfied == false && available
        self.lastNetworkSatisfied = available
        if restored { await self.syncAll(silent: true) }
      }
    }
    monitor.start(queue: DispatchQueue(label: "com.boxmail.network"))
    networkMonitor = monitor
  }
}
