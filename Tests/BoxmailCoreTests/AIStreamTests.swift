import Foundation
import Testing
@testable import BoxmailCore

@Test func aiStreamEventsDecodeUnicodeAndPerMailIdentity() throws {
  let json = #"{"type":"update","output":{"id":"j1","task":"translate","status":"running","text":"第一行\n第二行","messageId":"m1","attachmentId":null,"html":"<p>第一行</p>"}}"#
  let event = try JSONDecoder().decode(AIStreamEvent.self, from: Data(json.utf8))
  #expect(event.output?.messageId == "m1")
  #expect(event.output?.text == "第一行\n第二行")
  #expect(event.output?.html == "<p>第一行</p>")
  let snapshot = try JSONDecoder().decode(AIStreamEvent.self, from: Data(#"{"type":"snapshot","outputs":[]}"#.utf8))
  #expect(snapshot.outputs?.isEmpty == true)
}

@Test func formattedTranslationRoundTripsWithoutChangingOriginalMail() throws {
  let source = #"{"id":"m1","accountId":"a1","folder":"inbox","sender":"Sender","senderEmail":"s@example.com","to":"me@example.com","cc":"","subject":"Mail","body":"Hello","html":"<p>Hello</p>","translation":"你好","translationHTML":"<p>你好</p>","preview":"Hello","date":"2026-10-23T01:00:00Z","category":"未分类","unread":false,"starred":false,"attachmentIds":[]}"#
  let mail = try JSONDecoder().decode(MailMessage.self, from: Data(source.utf8))
  let restored = try JSONDecoder().decode(MailMessage.self, from: JSONEncoder().encode(mail))
  #expect(restored.body == "Hello")
  #expect(restored.html == "<p>Hello</p>")
  #expect(restored.translation == "你好")
  #expect(restored.translationHTML == "<p>你好</p>")
}
