import Foundation
import Testing
@testable import BoxmailCore

@Test func recipientCompletionKeepsQuotedCommasAndAddressesAroundCaret() {
  let value = #""Last, First" <first@example.com>, 张, keep@example.com"#
  let caret = (value as NSString).range(of: "张").location + 1
  let segment = RecipientCompletion.segment(in: value, caret: caret)
  #expect(segment.query == "张")
  let result = RecipientCompletion.replacing(value, segment: segment, name: "张三", email: "zhang@example.com")
  #expect(result.text == #""Last, First" <first@example.com>, "张三" <zhang@example.com>, keep@example.com"#)
  #expect(result.caret == (result.text as NSString).range(of: ", keep").location)
  let excluded = RecipientCompletion.addresses(in: [#""Last, First" <FIRST@example.com>"#, "other@example.com; first@example.com"])
  #expect(excluded == ["first@example.com", "other@example.com"])
}

@Test func recipientCompletionAppendsWithoutErasingExistingInputAndHandlesUnicodeCaret() {
  let input = "existing@example.com, 王𠀀"
  let segment = RecipientCompletion.segment(in: input, caret: (input as NSString).length)
  let result = RecipientCompletion.replacing(input, segment: segment, name: "王𠀀", email: "wang@example.com")
  #expect(result.text.hasPrefix("existing@example.com, "))
  #expect(result.text.hasSuffix(#""王𠀀" <wang@example.com>, "#))
  #expect(result.caret == (result.text as NSString).length)
}

@Test func quotedMailCollapsesOnlyRecognizedReplyContentAndHTMLQuotesRemainOptIn() {
  let text = "已确认，请按新排期执行。\n\nOn Tuesday, someone wrote:\n> 原来的排期"
  let split = QuotedMailText.split(text)
  #expect(split.visible == "已确认，请按新排期执行。")
  #expect(split.quoted.contains("原来的排期"))
  #expect(QuotedMailText.split("合同说明：\n正常正文").quoted.isEmpty)
  let html = "<p>新内容</p><blockquote>旧内容</blockquote>"
  #expect(QuotedMailText.hasHTMLQuote(html))
  #expect(!MailHTMLDocument.make(html: html, fontSize: 14, allowRemoteImages: false).contains("display: none !important"))
  #expect(MailHTMLDocument.make(html: html, fontSize: 14, allowRemoteImages: false, collapseQuotes: true).contains("display: none !important"))
}

@Test func structuredSearchBuilderQuotesNamesPhrasesAndEscapesValues() {
  let query = SearchQueryBuilder.make(terms: ["合同 审批", "from:literal"], conditions: [("from", "Last, First"), ("folder", "sent"), ("to", "")])
  #expect(query == #""合同 审批" "from:literal" from:"Last, First" folder:"sent""#)
  #expect(SearchQueryBuilder.quoted(#"A "quoted" name"#) == #""A \"quoted\" name""#)
}

@Test func backupAndPriorityWireContractsDecodeOptionalChecksumsAndCounts() throws {
  let data = Data(#"{"createdAt":"2026-10-21T00:00:00Z","counts":{"message":2,"draft":1,"attachment":1},"totalBytes":300,"credentialsIncluded":false,"sha256":"abc"}"#.utf8)
  let backup = try JSONDecoder().decode(BackupSummary.self, from: data)
  #expect(backup.counts["draft"] == 1)
  #expect(backup.sha256 == "abc")
  #expect(backup.previousBackup == nil)
  let catalog = try JSONDecoder().decode(CategoryResponse.self, from: Data(#"{"categories":[{"id":"custom","name":"合同审批","description":"需审核合同"}]}"#.utf8))
  #expect(catalog.categories[0].description == "需审核合同")
}

@Test func calendarSelectionKeepsLocalCalendarDaysAcrossTimeZones() throws {
  let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-20T18:00:00Z"))
  #expect(MailSearchCalendar.value(instant, timeZone: shanghai) == "2026-10-21")
  #expect(MailSearchCalendar.value(instant, timeZone: losAngeles) == "2026-10-20")
  for zone in [shanghai, losAngeles] {
    for day in ["2024-02-29", "2026-03-08", "2026-11-01"] {
      let picked = try #require(MailSearchCalendar.parse(day, timeZone: zone))
      #expect(MailSearchCalendar.value(picked, timeZone: zone) == day)
    }
  }
  #expect(MailSearchCalendar.parse("2026-02-29") == nil)
  #expect(MailSearchCalendar.parse("2026-13-01") == nil)
}

@Test func calendarMonthGridIncludesLeapDayAndStartsWeeksOnMonday() throws {
  let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
  let february = try #require(MailSearchCalendar.parse("2024-02-15", timeZone: zone))
  let cells = MailSearchCalendar.monthDays(containing: february, timeZone: zone)
  #expect(cells.count == 35)
  #expect(cells.prefix(3).allSatisfy { $0 == nil })
  let days = cells.compactMap { $0 }.map { MailSearchCalendar.value($0, timeZone: zone) }
  #expect(days.count == 29 && Set(days).count == 29)
  #expect(days.first == "2024-02-01" && days.last == "2024-02-29")
  let november = try #require(MailSearchCalendar.parse("2026-11-01", timeZone: zone))
  let sunday = MailSearchCalendar.monthDays(containing: november, timeZone: zone)
  #expect(sunday.prefix(6).allSatisfy { $0 == nil })
  #expect(sunday[6].map { MailSearchCalendar.value($0, timeZone: zone) } == "2026-11-01")
}
