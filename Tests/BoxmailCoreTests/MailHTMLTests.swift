import Foundation
import Testing
@testable import BoxmailCore

@Test func htmlMailWireFormatRemainsCompatibleWithOldTextMessages() throws {
  let legacy = #"{"id":"m1","accountId":"a1","folder":"inbox","sender":"Sender","senderEmail":"s@example.com","to":"me@example.com","cc":"","subject":"Mail","body":"Text","preview":"Text","date":"2026-10-14T01:00:00Z","category":"未分类","unread":false,"starred":false,"attachmentIds":[],"summary":null}"#
  let old = try JSONDecoder().decode(MailMessage.self, from: Data(legacy.utf8))
  #expect(old.html == nil)
  #expect(old.bodyVersion == nil)
  var object = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as! [String: Any]
  object["html"] = "<p>正文</p>"
  object["hasRemoteImages"] = true
  object["bodyVersion"] = 1
  let mail = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(mail.html == "<p>正文</p>")
  #expect(mail.hasRemoteImages == true)
  #expect(mail.bodyVersion == 1)
}

@Test func htmlDocumentBlocksRemoteContentUntilImagesAreRequested() {
  let blocked = MailHTMLDocument.make(html: "<p>正文</p>", fontSize: 14, allowRemoteImages: false)
  #expect(blocked.contains("img-src data:;"))
  #expect(blocked.contains("script-src 'none'"))
  #expect(blocked.contains("form-action 'none'"))
  let allowed = MailHTMLDocument.make(html: "<p>正文</p>", fontSize: 14, allowRemoteImages: true)
  #expect(allowed.contains("img-src data: https: http:;"))
  #expect(allowed.contains("connect-src 'none'"))
  #expect(MailHTMLDocument.externalLink(URL(string: "https://example.com")!))
  #expect(MailHTMLDocument.externalLink(URL(string: "mailto:me@example.com")!))
  #expect(!MailHTMLDocument.externalLink(URL(string: "file:///private/data")!))
  #expect(!MailHTMLDocument.externalLink(URL(string: "javascript:alert(1)")!))
}
