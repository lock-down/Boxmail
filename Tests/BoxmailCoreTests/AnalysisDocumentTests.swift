import Testing

@testable import BoxmailCore

@Test func existingChineseAnalysisSeparatesHeadingsAndInlineListsWithoutLosingFacts() {
  let blocks = AnalysisDocument.blocks(
    "文件主题：评审资料\n\n需要关注的问题：1）缺少签章。2）交付日期待确认。\n\n行动建议：1) 核对金额 1,280,000 元；2) 在 10 月 31 日前确认。")
  #expect(blocks.filter { $0.kind == .heading }.map(\.text) == ["文件主题", "需要关注的问题", "行动建议"])
  #expect(blocks.filter { $0.kind == .listItem }.count == 4)
  #expect(blocks.map(\.text).joined().contains("1,280,000"))
  #expect(blocks.map(\.text).joined().contains("10 月 31 日"))
}

@Test func markdownAnalysisRetainsInlineFormattingAndOrdinaryDocumentLines() {
  let blocks = AnalysisDocument.blocks(
    "## 主要结论\n\n**预算**已确认。\n下一步与负责人核对。\n\n- 周五前回复\n- 保留原链接 https://example.com")
  #expect(blocks.map(\.kind) == [.heading, .paragraph, .listItem, .listItem])
  #expect(blocks[1].text == "**预算**已确认。\n下一步与负责人核对。")
  #expect(blocks.last?.text.contains("https://example.com") == true)
}
