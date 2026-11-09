import AppKit
import Foundation
import Testing

@testable import BoxmailCore

@Suite(.serialized) @MainActor struct RichTextTests {
  @Test func semanticDocumentsRoundTripWithoutLosingUnicodeListsOrLinks() throws {
    let document = RichTextDocument(blocks: [
      .init(runs: [
        .init(text: "中文 e\u{301} 𠀀", bold: true),
        .init(text: "链接", link: "https://example.test/?a=1&b=2"),
      ]),
      .init(runs: []),
      .init(kind: "bullet", runs: [.init(text: "核对合同")]),
      .init(kind: "numbered", runs: [.init(text: "确认", italic: true)]),
      .init(kind: "numbered", runs: [.init(text: "回复")]),
      .init(runs: []),
    ])
    let attributed = RichTextCodec.attributed(document)
    #expect(attributed.string == document.plainText)
    #expect(RichTextCodec.document(attributed) == document)
    let encoded = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(RichTextDocument.self, from: encoded) == document)
  }

  @Test func layoutOnlySignatureAttributesNeverBecomeSavedRichText() {
    let document = RichTextDocument(text: "正文\n\n姓名\n公司")
    let attributed = NSMutableAttributedString(attributedString: RichTextCodec.attributed(document))
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacingBefore = 240
    attributed.addAttribute(
      .paragraphStyle, value: paragraph, range: NSRange(location: 4, length: 2))
    #expect(RichTextCodec.document(attributed) == document)
    #expect(!document.plainText.contains("\n\n\n"))
  }

  @Test func reopenedListMarkersMatchItemFontSizesAndIndentForDoubleDigitNumbers() throws {
    let document = RichTextDocument(
      blocks: (1...12).map { index in
        .init(kind: "numbered", runs: [.init(text: "第\(index)项正文", fontSize: 28, color: "#B42318")])
      } + [
        .init(kind: "numbered", runs: []),
        .init(kind: "bullet", runs: [.init(text: "项目符号", fontSize: 36)]),
        .init(kind: "bullet", runs: []),
      ])
    let restored = try JSONDecoder().decode(
      RichTextDocument.self, from: JSONEncoder().encode(document))
    let text = RichTextCodec.attributed(restored)
    var location = 0
    for index in document.blocks.indices {
      let range = (text.string as NSString).paragraphRange(
        for: NSRange(location: location, length: 0))
      let markerFont = try #require(
        text.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
      #expect(markerFont.pointSize == (index < 13 ? 28 : 36))
      let style = try #require(
        text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
      let prefix = index < 13 ? "\(index + 1). " : "• "
      #expect(
        style.headIndent >= (prefix as NSString).size(withAttributes: [.font: markerFont]).width)
      location = NSMaxRange(range)
    }
    #expect(RichTextCodec.document(text) == document)
  }

  @Test func pointSizesAndOpaqueColorsRoundTripWithOtherInlineStylesAndLegacyDocuments() throws {
    let document = RichTextDocument(blocks: [
      .init(
        kind: "bullet",
        runs: [
          .init(text: "重点", bold: true, italic: true, fontSize: 24, color: "#b42318"),
          .init(text: "链接", link: "https://example.test", fontSize: 12.75, color: "#3567af"),
          .init(text: "默认"),
        ])
    ])
    #expect(RichTextCodec.document(RichTextCodec.attributed(document)) == document)
    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(RichTextDocument.self, from: data) == document)
    let legacy = Data(
      #"{"blocks":[{"kind":"paragraph","runs":[{"text":"旧正文","bold":true,"italic":false}]}]}"#.utf8)
    let decoded = try JSONDecoder().decode(RichTextDocument.self, from: legacy)
    #expect(decoded.blocks[0].runs[0].fontSize == nil && decoded.blocks[0].runs[0].color == nil)
    #expect(RichTextCodec.document(RichTextCodec.attributed(decoded)) == decoded)
    #expect(RichTextRun(text: "默认", fontSize: 14, color: "#232d3d") == RichTextRun(text: "默认"))
  }

  @Test func compactDraftsKeepIdentityAndSyncStateWithoutLoadingRichBodies() throws {
    var draft = MailDraft(accountId: "a1", body: "正文")
    draft.richText = .init(blocks: [.init(runs: [.init(text: "正文", bold: true)])])
    draft.bodyHTML = "<p><strong>正文</strong></p>"
    draft.forwardedText = "转发原文"
    draft.forwardedHTML = "<p>转发原文</p>"
    draft.revision = "version"
    draft.syncState = "conflict"
    let header = draft.compact
    #expect(header.body.isEmpty && header.bodyLoaded == false)
    #expect(header.richText == nil && header.bodyHTML == nil && header.forwardedText == nil)
    #expect(header.revision == "version" && header.syncState == "conflict" && header.id == draft.id)
    var updated = draft
    updated.revision = "new version"
    updated.syncState = "synced"
    #expect(draft.hasSameContent(as: updated))
    updated.richText?.blocks[0].runs[0].bold = false
    #expect(!draft.hasSameContent(as: updated))
  }

  @Test func linksRejectActiveAndLocalSchemes() {
    for value in [
      "javascript:alert(1)", "file:///etc/passwd", "data:text/html,active", "//example.test",
      "https://example.test/\nsecret",
    ] {
      #expect(RichTextDocument.safeLink(value) == nil)
    }
    #expect(RichTextDocument.safeLink("mailto:person@example.test") != nil)
  }

  @Test func pastedWindowsLineEndingsBecomeValidParagraphsWithoutLosingContent() {
    let source = "第一行\r\n第二行\r末行"
    let document = RichTextCodec.document(NSAttributedString(string: source))
    #expect(document.plainText == "第一行\n第二行\n末行")
    #expect(document == RichTextDocument(text: source))
    #expect(
      document.blocks.allSatisfy {
        $0.runs.allSatisfy { !$0.text.contains("\r") && !$0.text.contains("\n") }
      })
  }

  @Test func legacyMailSummaryJobsAndConversationResultsDecodeIndependently() throws {
    let legacy = Data(
      #"{"subject":"test","nextSteps":[{"title":"回复","action":"reply","prompt":"确认"}]}"#.utf8)
    #expect(try JSONDecoder().decode(AgentResult.self, from: legacy).subject == "test")
    let conversation = Data(
      #"{"progress":[{"text":"已确认","messageIds":["m1"]}],"conversationNextSteps":[{"text":"回复","messageIds":["m1"]}],"sourceMessages":[{"id":"m1","sender":"同事","subject":"排期","date":"2026-11-09T00:00:00Z"}],"contextFingerprint":"hash","partial":false}"#
        .utf8)
    let result = try JSONDecoder().decode(AgentResult.self, from: conversation)
    #expect(result.progress?.first?.messageIds == ["m1"])
    #expect(result.conversationNextSteps?.first?.text == "回复")
  }
}
