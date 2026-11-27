import Foundation

public struct AIStreamOutput: Codable, Identifiable, Equatable {
  public var id, task, status, text: String
  public var accountId, messageId, attachmentId, parentJobId, stage, html, targetLanguage: String?
  public var thought: Bool?
  public var thinkingSummary: String?
  public var tools: [AIToolActivity]?
}

public struct AIToolActivity: Codable, Identifiable, Equatable {
  public var id, name, status: String
  public var detail: String?
}

public struct AIStreamEvent: Decodable {
  public var type: String
  public var outputs: [AIStreamOutput]?
  public var output: AIStreamOutput?
}
