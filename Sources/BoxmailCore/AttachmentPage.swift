import Foundation

public struct AttachmentPage: Codable {
  public let items: [AttachmentPageItem]
  public let total, offset, limit, accountTotal, analyzedTotal: Int
}

public struct AttachmentPageItem: Codable, Identifiable, Hashable {
  public let attachment: MailAttachment
  public let source: AttachmentPageSource
  public var id: String { attachment.id }
  public var name: String { attachment.name }
  public var size: Int { attachment.size }
  public var date: String { source.date }
}

public struct AttachmentPageSource: Codable, Hashable {
  public let id, subject, sender, date: String
}
