import AppKit
import BoxmailCore
import Network

extension MailStore {
  var mailQueryKey: String {
    [accountId, destination.rawValue, filter, search, String(searchAllAccounts)].joined(separator: "\u{1f}")
  }
  var currentSyncFolder: MailSyncFolder? {
    syncSnapshot?.folders.first { $0.accountId == accountId && $0.folder == destination.rawValue }
  }

  func loadMessages(reset: Bool, preserveSelection: Bool = false) async {
    let key = mailQueryKey
    let selectionWasInQuery =
      pageKey == key
      && selectedMessageId.map { id in filteredMessages.contains { $0.id == id } } == true
    let keepSelection =
      (preserveSelection && pageKey == key)
      || (pinnedQueryKey == key && pinnedMessageId == selectedMessageId)
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
    do {
      let page: MailPage = try await BackendService.shared.request(
        "/messages?\(query.percentEncodedQuery ?? "")")
      try Task.checkCancellation()
      guard pageGeneration == generation, key == mailQueryKey else { return }
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
    } catch is CancellationError {
    } catch {
      guard pageGeneration == generation else { return }
      listError = error.localizedDescription
    }
  }

  func loadSelectedMessage() async {
    guard let id = selectedMessageId else { return }
    let generation = UUID()
    detailGeneration = generation
    detailError = nil
    do {
      let full: MailMessage = try await BackendService.shared.request("/messages/\(id)")
      try Task.checkCancellation()
      guard id == selectedMessageId, generation == detailGeneration else { return }
      // Keep only the selected body; headers and summaries remain available for overview screens.
      detailCache = [id: full]
      for aid in full.attachmentIds { await loadAttachment(aid) }
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
    do {
      let full: MailAttachment = try await BackendService.shared.request(
        "/attachments/\(id)/metadata")
      try Task.checkCancellation()
      attachmentCache[id] = full
      if let index = attachments.firstIndex(where: { $0.id == id }) { attachments[index] = full }
    } catch is CancellationError {
    } catch { mailAIErrors[selectedMessageId ?? ""] = "附件内容加载失败，可重新打开邮件重试。" }
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
