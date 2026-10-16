import Foundation
import Testing

@testable import BoxmailCore

@Test func aiSettingsContractHasEffortAndNonemptyEditableDefaults() throws {
  var config = AIConfig()
  #expect(config.model == "deepseek-flash")
  #expect(config.effort == "high")
  #expect(config.prompts.count == 6)
  #expect(config.prompts.values.allSatisfy { !$0.isEmpty })
  config.effort = "max"
  config.prompts["reply"] = "使用正式语气"
  let data = try JSONEncoder().encode(config)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["temperature"] == nil)
  #expect(object["maxTokens"] == nil)
  #expect(object["tokenParameter"] == nil)
  let decoded = try JSONDecoder().decode(AIConfig.self, from: data)
  #expect(decoded.effort == "max")
  #expect(decoded.prompts["reply"] == "使用正式语气")
}

@Test func imageAndScannedPDFCanBeAnalyzedWithoutExtractedText() throws {
  for (name, contentType) in [("图.png", "image/png"), ("扫描件.pdf", "application/pdf")] {
    let object: [String: Any] = [
      "id": "a1", "messageId": "m1", "name": name, "contentType": contentType,
      "path": "/tmp/file", "text": "", "parseError": "", "date": "2026-10-13", "size": 100,
    ]
    let attachment = try JSONDecoder().decode(
      MailAttachment.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(attachment.canAnalyze)
  }
}

@Test func replyPresetsLoadSharedResourceAndRetainDistinctIntentRules() {
  #expect(ReplyPreset.allCases.map(\.title) == ["感兴趣回复", "不感兴趣回复", "感谢回复"])
  #expect(Set(ReplyPreset.allCases.map(\.rawValue)).count == 3)
  #expect(ReplyPreset.allCases.allSatisfy { !$0.detail.isEmpty && !$0.instruction.isEmpty })
  #expect(ReplyPreset.interested.instruction.contains("兴趣不等于接受邀请"))
  #expect(ReplyPreset.decline.instruction.contains("不要编造"))
  #expect(ReplyPreset.thanks.instruction.contains("感谢不代表同意"))
}
