import Foundation
import Testing
@testable import BoxmailCore

@Test func overviewMembershipNeverRemovesTheMailSummary() throws {
  let source = #"{"id":"m1","accountId":"a1","folder":"inbox","sender":"Test","senderEmail":"s@example.test","to":"me@example.test","cc":"","subject":"Review","body":"Source","preview":"Source","date":"2026-10-23T00:00:00Z","category":"未分类","unread":false,"starred":false,"attachmentIds":[],"summary":{"points":["核对排期"],"todos":[{"id":"t1","title":"确认排期","due":"周五","done":false}],"keyInfo":[]}}"#
  var mail = try JSONDecoder().decode(MailMessage.self, from: Data(source.utf8))
  #expect(mail.isInSummaryOverview)
  mail.summaryHidden = true
  let restored = try JSONDecoder().decode(MailMessage.self, from: JSONEncoder().encode(mail))
  #expect(!restored.isInSummaryOverview)
  #expect(restored.summary?.points == ["核对排期"])
  #expect(restored.summary?.todos.first?.title == "确认排期")
  #expect(restored.body == "Source")
  mail.summaryHidden = false
  #expect(mail.isInSummaryOverview)
  mail.folder = "trash"
  #expect(!mail.isInSummaryOverview)
  #expect(mail.summary != nil)
}
