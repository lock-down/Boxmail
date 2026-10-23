import Foundation

public struct AIStreamOutput: Codable, Identifiable {
  public var id, task, status, text: String
  public var accountId, messageId, attachmentId, parentJobId, stage, html: String?
}

public struct AIStreamEvent: Decodable {
  public var type: String
  public var outputs: [AIStreamOutput]?
  public var output: AIStreamOutput?
}
