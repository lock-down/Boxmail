import Foundation

public struct MailSenderGroup: Codable, Identifiable, Hashable {
  public let id, accountId, senderEmail, latestMessageId: String
  public let count, unreadCount: Int

  public init(id: String, accountId: String, senderEmail: String, latestMessageId: String,
    count: Int, unreadCount: Int) {
    self.id = id; self.accountId = accountId; self.senderEmail = senderEmail
    self.latestMessageId = latestMessageId; self.count = count; self.unreadCount = unreadCount
  }

  public func contains(_ message: MailMessage) -> Bool {
    guard message.accountId == accountId, message.draftId == nil else { return false }
    if senderEmail.isEmpty { return message.id == latestMessageId }
    return message.senderEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == senderEmail
  }
}

public extension MailMessage {
  static func sortedNewestFirst(_ messages: [MailMessage]) -> [MailMessage] {
    let fractional = ISO8601DateFormatter(), standard = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let dated: [(message: MailMessage, date: Date)] = messages.map { message in
      let date = fractional.date(from: message.date) ?? standard.date(from: message.date) ?? Date.distantPast
      return (message, date)
    }
    return dated.sorted { a, b in
      a.date == b.date ? a.message.id < b.message.id : a.date > b.date
    }.map { $0.message }
  }
}
