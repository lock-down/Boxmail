import Foundation

public struct MailAIContext: Codable, Hashable {
  public let attachments: [MailAIContextSource]
  public let partial: Bool
  public var readableCount: Int { attachments.filter { $0.status != "unavailable" }.count }
}

public struct MailAIContextSource: Codable, Hashable, Identifiable {
  public let id, name, status: String
  public let reason: String?
  public let entries: [MailAIContextSource]?
}
