import Foundation

public struct MailMessagePatch: Codable, Equatable {
  public var folder: String?
  public var category: String?
  public var unread: Bool?
  public var starred: Bool?

  public init(folder: String? = nil, category: String? = nil,
    unread: Bool? = nil, starred: Bool? = nil) {
    self.folder = folder
    self.category = category
    self.unread = unread
    self.starred = starred
  }

  public var payload: [String: Any] {
    var values: [String: Any] = [:]
    if let folder { values["folder"] = folder }
    if let category { values["category"] = category }
    if let unread { values["unread"] = unread }
    if let starred { values["starred"] = starred }
    return values
  }
}

public struct MailUndoItem: Codable {
  public let id: String
  public let changes: MailMessagePatch
  public let expected: MailMessagePatch
  public var payload: [String: Any] {
    ["id": id, "changes": changes.payload, "expected": expected.payload]
  }
}

public struct MailBatchResponse: Decodable {
  public let changedCount: Int
  public let undo: [MailUndoItem]
}
