import BoxmailCore
import Foundation

extension MailStore {
  func loadConversation(reset: Bool = true) async {
    guard let id = selectedMessageId else { return }
    let generation = detailGeneration
    if reset && conversationAnchor != id {
      conversation = nil; conversationBodies = [:]; conversationError = nil
    }
    conversationAnchor = id
    do {
      let offset = reset ? 0 : conversation?.nextOffset ?? 0
      var result: MailConversation = try await BackendService.shared.request("/messages/\(id)/thread?offset=\(offset)&limit=100")
      try Task.checkCancellation()
      guard selectedMessageId == id, generation == detailGeneration else { return }
      if !reset, let existing = conversation {
        let ids = Set(existing.messages.map(\.id))
        result.messages = existing.messages + result.messages.filter { !ids.contains($0.id) }
      }
      if !result.messages.contains(where: { $0.id == id }), let header = messages.first(where: { $0.id == id }) {
        result.messages.append(header)
      }
      result.messages.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
      conversation = result; conversationError = nil
      if let body = detailCache[id] { conversationBodies[id] = body }
    } catch is CancellationError {} catch {
      if selectedMessageId == id { conversationError = error.localizedDescription }
    }
  }
  func loadConversationBody(_ header: MailMessage) async {
    guard let anchor = conversationAnchor else { return }
    if conversationBodies[header.id] != nil { return }
    do {
      let full: MailMessage = try await BackendService.shared.request("/messages/\(header.id)")
      try Task.checkCancellation()
      guard conversationAnchor == anchor, conversation?.accountId == full.accountId,
        conversation?.messages.contains(where: { $0.id == full.id }) == true else { return }
      conversationBodies[full.id] = full
      for id in full.attachmentIds { await loadAttachment(id) }
    } catch is CancellationError {} catch { conversationError = error.localizedDescription }
  }
}
