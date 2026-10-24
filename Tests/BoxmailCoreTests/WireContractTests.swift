import Foundation
import Testing

@testable import BoxmailCore

@Test func formattedForwardDraftRetainsQuotedHTMLAndEditableIntroduction() throws {
  let raw = #"{"id":"forward1","accountId":"a1","to":"","cc":"","bcc":"","subject":"Fwd: 原邮件","body":"转发说明","status":"draft","updatedAt":"2026-10-24T00:00:00Z","attachmentIds":[],"forwardedHTML":"<table><tr><td>原邮件</td></tr></table>","forwardedText":"原邮件"}"#
  let draft = try JSONDecoder().decode(MailDraft.self, from: Data(raw.utf8))
  #expect(draft.body == "转发说明")
  #expect(draft.forwardedHTML?.contains("<table>") == true)
  let reopened = try JSONDecoder().decode(MailDraft.self, from: JSONEncoder().encode(draft))
  #expect(reopened.forwardedHTML == draft.forwardedHTML)
  #expect(reopened.forwardedText == "原邮件")
  let legacy = MailDraft(accountId: "a1", body: "旧草稿")
  let decoded = try JSONDecoder().decode(MailDraft.self, from: JSONEncoder().encode(legacy))
  #expect(decoded.forwardedHTML == nil)
  #expect(decoded.body == "旧草稿")
}

@Test func decodeClassificationWithUnknownFields() throws {
  let data = Data(
    #"{"id":"job1","task":"classify","status":"needsApproval","createdAt":"2026-10-13T01:00:00Z","messageId":null,"error":null,"result":{"items":[{"id":"m1","category":"工作项目","reason":"排期"}],"previous":[]}}"#
      .utf8)
  let job = try JSONDecoder().decode(AgentJob.self, from: data)
  #expect(job.result?.items?.first?.category == "工作项目")
  #expect(job.status == "needsApproval")
  #expect(job.preview == nil)
  #expect(job.attachmentItems == nil)
  #expect(job.replyPreset == nil)
}

@Test func attachmentBatchContractPreservesPerFileProgressAndErrors() throws {
  let data = Data(
    #"{"id":"b1","task":"attachmentBatch","status":"partial","createdAt":"2026-10-19T01:00:00Z","messageId":"m1","accountId":"a1","progress":{"total":4,"completed":2,"failed":1,"batchSize":1,"batch":1},"attachmentItems":[{"id":"a1","name":"已有.docx","status":"existing","error":null},{"id":"a2","name":"本次.xlsx","status":"completed","error":null},{"id":"a3","name":"失败.pdf","status":"failed","error":"理解超时"},{"id":"a4","name":"归档.zip","status":"unsupported","error":"暂不支持"}]}"#
      .utf8)
  let job = try JSONDecoder().decode(AgentJob.self, from: data)
  #expect(job.attachmentItems?.filter(\.isAnalyzed).count == 2)
  #expect(job.attachmentItems?.allSatisfy(\.isFinished) == true)
  #expect(job.attachmentItems?[2].error == "理解超时")
  let roundTrip = try JSONDecoder().decode(AgentJob.self, from: JSONEncoder().encode(job))
  #expect(roundTrip.attachmentItems?.map(\.status) == ["existing", "completed", "failed", "unsupported"])
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
  #expect(message.summary?.overviewText == "项目排期已确认")
  #expect(message.summary?.nextSteps == nil)
  #expect(message.messageId == nil)
  #expect(message.restoreFolder == nil)
  #expect(message.unarchiveFolder == nil)
}

@Test func archivedMailDecodesItsOriginalMailboxAndUndoAction() throws {
  let raw = #"{"id":"m1","accountId":"a1","folder":"archive","sender":"Me","senderEmail":"me@example.com","to":"to@example.com","cc":"","subject":"测试","body":"正文","preview":"正文","date":"2026-10-20T00:00:00Z","category":"未分类","unread":false,"starred":false,"attachmentIds":[],"unarchiveFolder":"sent"}"#
  var message = try JSONDecoder().decode(MailMessage.self, from: Data(raw.utf8))
  #expect(message.unarchiveTitle == "取消归档，回到已发送")
  let decoded = try JSONDecoder().decode(MailMessage.self, from: JSONEncoder().encode(message))
  #expect(decoded.unarchiveFolder == "sent")
  message.unarchiveFolder = nil
  #expect(message.unarchiveTitle == "取消归档，回到收件箱")
}

@Test func trashRestoreTargetDecodesAndNamesTheOriginalMailbox() throws {
  let raw = #"{"id":"m1","accountId":"a1","folder":"trash","sender":"Me","senderEmail":"me@example.com","to":"to@example.com","cc":"","subject":"测试","body":"正文","preview":"正文","date":"2026-10-20T00:00:00Z","category":"未分类","unread":false,"starred":false,"attachmentIds":[],"restoreFolder":"sent"}"#
  var message = try JSONDecoder().decode(MailMessage.self, from: Data(raw.utf8))
  #expect(message.restoreTitle == "恢复到已发送")
  let decoded = try JSONDecoder().decode(MailMessage.self, from: JSONEncoder().encode(message))
  #expect(decoded.restoreFolder == "sent")
  for (folder, title) in [("inbox", "收件箱"), ("archive", "已归档"), ("drafts", "草稿箱"), ("spam", "垃圾邮件")] {
    message.restoreFolder = folder
    #expect(message.restoreTitle == "恢复到\(title)")
  }
  message.restoreFolder = nil
  #expect(message.restoreTitle == "恢复到收件箱")
}

@Test func compactSummaryRetainsSuggestedActionsAndCopiesAllSections() throws {
  let raw = #"{"overview":"报名需回复邮件，10月22日11点前提交。","points":[],"todos":[{"id":"t1","title":"提交应答资料","due":"10月22日11点","done":false}],"keyInfo":[{"label":"联系人","value":"项目联系人"}],"nextSteps":[{"title":"起草报名回复","action":"reply","prompt":"请起草待审核回复，不声称已提交附件。"},{"title":"核对附件要求","action":"attachments","prompt":""},{"title":"核算报价并盖章","action":"note","prompt":""}]}"#
  let summary = try JSONDecoder().decode(MailSummary.self, from: Data(raw.utf8))
  #expect(summary.overviewText == "报名需回复邮件，10月22日11点前提交。")
  #expect(summary.nextSteps?.map(\.action) == ["reply", "attachments", "note"])
  #expect(summary.plainText.contains("内容概要："))
  #expect(summary.plainText.contains("[ ] 提交应答资料（10月22日11点）"))
  #expect(summary.plainText.contains("您可继续："))
  #expect(summary.plainText.contains("联系人：项目联系人"))
  let decoded = try JSONDecoder().decode(MailSummary.self, from: JSONEncoder().encode(summary))
  #expect(decoded == summary)
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

@Test func pagedHeadersAndPersistentSyncProgressDecodeWithoutLoadingBody() throws {
  let raw =
    #"{"messages":[{"id":"m1","accountId":"a1","folder":"inbox","sender":"A","senderEmail":"a@example.com","to":"me@example.com","cc":"","subject":"测试","body":"","preview":"摘要","date":"2026-10-19T00:00:00Z","category":"未分类","unread":true,"starred":false,"attachmentIds":[],"bodyLoaded":false,"replyTo":"reply@example.com","references":["<root@example.com>"]}],"total":1005,"nextOffset":100}"#
  let page = try JSONDecoder().decode(MailPage.self, from: Data(raw.utf8))
  #expect(page.total == 1005)
  #expect(page.messages.first?.bodyLoaded == false)
  #expect(page.messages.first?.references == ["<root@example.com>"])
  let sync =
    #"{"runningAccounts":["a1"],"folders":[{"id":"s1","accountId":"a1","folder":"inbox","status":"partial","downloaded":200,"total":1005,"remaining":805,"hasMore":true}],"results":[]}"#
  let state = try JSONDecoder().decode(MailSyncSnapshot.self, from: Data(sync.utf8))
  #expect(state.folders.first?.remaining == 805)
  #expect(state.folders.first?.hasMore == true)
}
