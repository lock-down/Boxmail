import Foundation
import Testing

@testable import BoxmailCore

@Test func decodeClassificationWithUnknownFields() throws {
  let data = Data(
    #"{"id":"job1","task":"classify","status":"needsApproval","createdAt":"2026-10-13T01:00:00Z","messageId":null,"error":null,"result":{"items":[{"id":"m1","category":"工作项目","reason":"排期"}],"previous":[]}}"#
      .utf8)
  let job = try JSONDecoder().decode(AgentJob.self, from: data)
  #expect(job.result?.items?.first?.category == "工作项目")
  #expect(job.status == "needsApproval")
  #expect(job.preview == nil)
  #expect(job.replyPreset == nil)
}

@Test func replyPreviewContractRetainsAttitudeAndExplicitDraftAssociation() throws {
  let data = Data(
    #"{"id":"reply1","task":"reply","status":"completed","createdAt":"2026-10-16T01:00:00Z","messageId":"m1","replyPreset":"thanks","preview":true,"result":{"subject":"Re: 评审","body":"谢谢，已收到。","draftId":"d1"}}"#
      .utf8)
  let job = try JSONDecoder().decode(AgentJob.self, from: data)
  #expect(job.preview == true)
  #expect(job.replyPreset.flatMap(ReplyPreset.init(rawValue:)) == .thanks)
  #expect(job.result?.body == "谢谢，已收到。")
  #expect(job.result?.draftId == "d1")
  let encoded = try JSONEncoder().encode(job)
  let decoded = try JSONDecoder().decode(AgentJob.self, from: encoded)
  #expect(decoded.replyPreset == job.replyPreset)
  #expect(decoded.preview == job.preview)
}
@Test func decodeSummaryJobAndMail() throws {
  let data = Data(
    #"{"id":"m1","accountId":"a1","folder":"inbox","sender":"陈嘉禾","senderEmail":"chen@example.com","to":"me@example.com","cc":"","subject":"评审","body":"会议内容","preview":"会议内容","date":"2026-10-13T01:00:00Z","category":"工作项目","unread":true,"starred":false,"attachmentIds":[],"summary":{"points":["项目排期已确认"],"todos":[{"id":"t1","title":"回执","due":"周五","done":false}],"keyInfo":[]},"uid":2,"uidValidity":"12345"}"#
      .utf8)
  let message = try JSONDecoder().decode(MailMessage.self, from: data)
  #expect(message.summary?.todos.first?.done == false)
  #expect(message.messageId == nil)
}

@Test func decodeBackgroundOrganizationProgress() throws {
  let data = Data(
    #"{"id":"j2","task":"classify","status":"partial","createdAt":"2026-10-16T01:00:00Z","messageIds":["m1","m2"],"completedIds":["m1"],"progress":{"total":2,"completed":1,"failed":1,"batchSize":6,"batch":1},"result":{"items":[{"id":"m1","category":"工作项目","reason":"评审"}]}}"#
      .utf8)
  let job = try JSONDecoder().decode(AgentJob.self, from: data)
  #expect(job.progress?.completed == 1)
  #expect(job.progress?.total == 2)
  #expect(job.result?.items?.count == 1)
  #expect(job.status == "partial")
}
