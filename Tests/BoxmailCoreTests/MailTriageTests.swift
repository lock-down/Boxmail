import Foundation
import Testing
@testable import BoxmailCore

@Test func batchUndoContractKeepsFalseValuesAndOnlyChangedFields() throws {
  let raw = #"{"changedCount":1,"undo":[{"id":"m1","changes":{"unread":false,"folder":"sent"},"expected":{"unread":true,"folder":"archive"}}]}"#
  let response = try JSONDecoder().decode(MailBatchResponse.self, from: Data(raw.utf8))
  #expect(response.changedCount == 1)
  let item = try #require(response.undo.first)
  #expect(item.changes.unread == false)
  #expect(item.changes.starred == nil)
  #expect(item.expected.folder == "archive")
  let payload = try JSONSerialization.data(withJSONObject: item.payload)
  let decoded = try JSONDecoder().decode(MailUndoItem.self, from: payload)
  #expect(decoded.changes == item.changes)
  #expect(decoded.expected == item.expected)
}
