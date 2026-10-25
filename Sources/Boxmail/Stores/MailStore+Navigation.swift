import Foundation

struct MailRevealRequest: Equatable {
  let id = UUID()
  let messageId: String
  let queryKey: String
}

extension MailStore {
  var readyMailReveal: MailRevealRequest? {
    guard let request = mailRevealRequest, request.queryKey == mailQueryKey,
      selectedMessageId == request.messageId, selectedMessageIds == [request.messageId],
      filteredMessages.contains(where: { $0.id == request.messageId }) else { return nil }
    return request
  }

  func finishMailReveal(_ request: MailRevealRequest) {
    if mailRevealRequest == request { mailRevealRequest = nil }
  }
}
