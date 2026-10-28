import BoxmailCore
import Foundation

extension MailStore {
  var usesSenderGroups: Bool { groupMailBySender && senderGroupsLoaded && pageKey == mailQueryKey }

  var visibleSenderMessages: [MailMessage] {
    let latest = Dictionary(pageMessages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    return senderGroups.flatMap { group -> [MailMessage] in
      guard let header = latest[group.latestMessageId] else { return [] }
      return [header] + (expandedSenderGroups.contains(group.id) ? senderChildren(group) : [])
    }
  }

  func senderChildren(_ group: MailSenderGroup) -> [MailMessage] {
    (senderGroupMessages[group.id] ?? []).filter { $0.id != group.latestMessageId }
  }

  func senderLoadedCount(_ group: MailSenderGroup) -> Int {
    Set([group.latestMessageId] + (senderGroupMessages[group.id] ?? []).map(\.id)).count
  }

  func changeSenderGrouping(_ enabled: Bool) {
    guard groupMailBySender != enabled else { return }
    let target = selectedMessage
    groupMailBySender = enabled
    if let target {
      pinnedMessageId = target.id
      pinnedQueryKey = mailQueryKey
      mailRevealRequest = MailRevealRequest(messageId: target.id, queryKey: mailQueryKey)
    }
  }

  func clearSenderGroups() {
    senderGroups = []
    senderGroupTotal = 0
    senderGroupsLoaded = false
    expandedSenderGroups = []
    senderGroupMessages = [:]
    senderGroupNextOffsets = [:]
    senderGroupLoading = []
    senderGroupErrors = [:]
    senderGroupGenerations = [:]
    senderGroupRevision = UUID()
    senderRevealedMessage = nil
  }

  func applySenderGroupPage(_ page: MailPage, reset: Bool, key: String, preserveSelection: Bool) {
    guard key == mailQueryKey, let incoming = page.senderGroups else { return }
    let sameQuery = pageKey == key
    let keepSelection =
      preserveSelection && sameQuery
      || pinnedQueryKey == key && pinnedMessageId == selectedMessageId
    if reset {
      if !sameQuery { clearSenderGroups() }
      senderGroupRevision = UUID()
      senderGroupGenerations = [:]
      senderGroupLoading = []
      senderGroupErrors = [:]
      senderGroups = incoming
      pageMessages = page.messages
      senderRevealedMessage = page.revealedMessage
    } else {
      for group in incoming {
        if let index = senderGroups.firstIndex(where: { $0.id == group.id }) {
          senderGroups[index] = group
        } else {
          senderGroups.append(group)
        }
      }
      let headers = Dictionary(
        (pageMessages + page.messages).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
      pageMessages = Array(headers.values)
    }
    let ordered = MailMessage.sortedNewestFirst(pageMessages)
    let ranks = Dictionary(
      ordered.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { old, _ in old })
    senderGroups.sort { (ranks[$0.latestMessageId] ?? .max) < (ranks[$1.latestMessageId] ?? .max) }
    let ids = Set(senderGroups.filter { $0.count > 1 }.map(\.id))
    expandedSenderGroups.formIntersection(ids)
    // Collapsed members are not fetched during refresh. Drop their old snapshot
    // so reopening the group cannot resurrect moved mail or stale flags/offsets.
    let retainedIds = reset ? expandedSenderGroups : ids
    senderGroupMessages = senderGroupMessages.filter { retainedIds.contains($0.key) }
    senderGroupNextOffsets = senderGroupNextOffsets.filter { retainedIds.contains($0.key) }
    if let revealed = page.revealedMessage, revealed.id == selectedMessageId,
      let group = senderGroups.first(where: { $0.contains(revealed) }), group.count > 1,
      revealed.id != group.latestMessageId
    {
      expandedSenderGroups.insert(group.id)
      let retained = (senderGroupMessages[group.id] ?? []).filter { $0.id != revealed.id }
      senderGroupMessages[group.id] = MailMessage.sortedNewestFirst(retained + [revealed])
    }
    pageKey = key
    pageTotal = page.total
    nextOffset = page.nextOffset
    senderGroupTotal = page.groupTotal ?? senderGroups.count
    senderGroupsLoaded = true
    if reset
      && (!keepSelection || !visibleSenderMessages.contains(where: { $0.id == selectedMessageId }))
    {
      selectedMessageId = visibleSenderMessages.first?.id
      selectedMessageIds = selectedMessageId.map { [$0] } ?? []
      mailAITab = nil
    }
    reconcileMailSelection()
  }

  func toggleSenderGroup(_ id: String) {
    guard usesSenderGroups, let group = senderGroups.first(where: { $0.id == id }), group.count > 1
    else { return }
    if expandedSenderGroups.contains(id) {
      let hidden = Set(senderChildren(group).map(\.id))
      let wasSelected = !selectedMessageIds.isDisjoint(with: hidden)
      expandedSenderGroups.remove(id)
      var selection = selectedMessageIds.subtracting(hidden)
      if selection.isEmpty && wasSelected { selection.insert(group.latestMessageId) }
      setMailSelection(selection, for: mailQueryKey)
    } else {
      expandedSenderGroups.insert(id)
      if senderGroupMessages[id] == nil || senderGroupErrors[id] != nil {
        Task { await loadSenderGroup(id, reset: true) }
      }
    }
  }

  func expandSelectedSenderGroup() -> Bool {
    guard usesSenderGroups, selectedMessageIds.count == 1,
      let group = senderGroups.first(where: { $0.latestMessageId == selectedMessageId }),
      group.count > 1, !expandedSenderGroups.contains(group.id)
    else { return false }
    toggleSenderGroup(group.id)
    return true
  }

  func collapseSelectedSenderGroup() -> Bool {
    guard usesSenderGroups, let selectedMessage,
      let group = senderGroups.first(where: { $0.contains(selectedMessage) }),
      expandedSenderGroups.contains(group.id)
    else { return false }
    toggleSenderGroup(group.id)
    return true
  }

  func loadSenderGroup(_ id: String, reset: Bool) async {
    guard usesSenderGroups, senderGroups.contains(where: { $0.id == id }),
      reset || (!senderGroupLoading.contains(id) && senderGroupNextOffsets[id] != nil)
    else { return }
    let key = mailQueryKey
    let revision = senderGroupRevision
    let generation = UUID()
    let restore = restoreRevision
    senderGroupGenerations[id] = generation
    senderGroupLoading.insert(id)
    senderGroupErrors[id] = nil
    defer {
      if senderGroupGenerations[id] == generation { senderGroupLoading.remove(id) }
    }
    var query = URLComponents()
    query.queryItems = [
      URLQueryItem(
        name: "accountId", value: !search.isEmpty && searchAllAccounts ? nil : accountId),
      URLQueryItem(name: "folder", value: destination.rawValue),
      URLQueryItem(name: "q", value: search),
      URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "senderGroup", value: id),
      URLQueryItem(name: "offset", value: String(reset ? 0 : senderGroupNextOffsets[id] ?? 0)),
      URLQueryItem(
        name: "limit",
        value: String(reset ? min(200, max(100, senderGroupMessages[id]?.count ?? 0)) : 100)),
    ]
    let encodedQuery = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
    do {
      let page: MailPage = try await backend.request("/messages?\(encodedQuery)")
      try Task.checkCancellation()
      guard key == mailQueryKey, revision == senderGroupRevision, restore == restoreRevision,
        senderGroupGenerations[id] == generation
      else { return }
      var values = reset ? page.messages : (senderGroupMessages[id] ?? []) + page.messages
      if let revealed = senderRevealedMessage,
        let group = senderGroups.first(where: { $0.id == id }),
        group.contains(revealed), !values.contains(where: { $0.id == revealed.id })
      {
        values.append(revealed)
      }
      senderGroupMessages[id] = MailMessage.sortedNewestFirst(
        Array(
          Dictionary(
            values.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
          ).values))
      senderGroupNextOffsets[id] = page.nextOffset
      reconcileMailSelection()
    } catch is CancellationError {
    } catch {
      guard key == mailQueryKey, revision == senderGroupRevision, restore == restoreRevision,
        senderGroupGenerations[id] == generation
      else { return }
      senderGroupErrors[id] = error.localizedDescription
    }
  }
}
