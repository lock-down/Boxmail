import Foundation
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

@Test func chineseEmphasisNextToPunctuationRendersWithoutLeakingMarkdownMarkers() {
  let text = AnalysisDocument.inlineText("**结论：**报名需完整。*注意：*逾期视为放弃。")
  #expect(!String(text.characters).contains("**"))
  #expect(String(text.characters).contains("结论："))
  #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
  #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
  let code = AnalysisDocument.inlineText("使用 `**注意：**保持原样` 或 ``a|b`` 核对。")
  #expect(String(code.characters).contains("**注意：**保持原样"))
  #expect(String(code.characters).contains("a|b"))
  #expect(code.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.count == 2)
}

@Test func markdownTablesKeepAlignedColumnsEscapedPipesAndInlineCode() throws {
  let blocks = AnalysisDocument.blocks(
    "## 数据\n\n| 项目 | 金额 | 说明 |\n| :--- | ---: | :---: |\n| 项目 A | **1,280,000 元** | `A|B` |\n| 项目 B | 300 元 | 甲\\|乙 |\n\n> 金额以原件为准。")
  let table = try #require(blocks.first { $0.kind == .table }?.table)
  #expect(table.headers == ["项目", "金额", "说明"])
  #expect(table.alignments == [.leading, .trailing, .center])
  #expect(table.rows[0] == ["项目 A", "**1,280,000 元**", "`A|B`"])
  #expect(table.rows[1][2] == "甲|乙")
  #expect(blocks.last?.kind == .quote)
}

@Test func fencedCodeKeepsWhitespaceAndDoesNotApplyLegacyHeadingNormalization() throws {
  let source = "```text\n文件主题：不要转换\n  1) 保留代码。2) 保留代码\n| a | b |\n```\n\n## 结论\n正文。"
  let blocks = AnalysisDocument.blocks(source)
  #expect(blocks.map(\.kind) == [.code, .heading, .paragraph])
  #expect(blocks[0].language == "text")
  #expect(blocks[0].text == "文件主题：不要转换\n  1) 保留代码。2) 保留代码\n| a | b |")
  #expect(AnalysisDocument.blocks("~~~\n未闭合代码\n## 原样保留").first?.text == "未闭合代码\n## 原样保留")
}

@Test func markdownHeadingLevelsTaskListsNestingRulesAndDecimalsRemainDistinct() {
  let blocks = AnalysisDocument.blocks(
    "标题\n===\n\n## 要求\n\n- [ ] 核对金额\n  - [x] 确认附件\n1. 回复来信\n\n1.25 万元\n2026.10.22 截止\n\n---\n\n> **注意**：仅供核对。")
  #expect(blocks[0].level == 1)
  #expect(blocks[1].level == 2)
  let items = blocks.filter { $0.kind == .listItem }
  #expect(items.count == 3)
  #expect(items[0].checked == false)
  #expect(items[1].checked == true)
  #expect(items[1].level == 1)
  #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("1.25 万元") && $0.text.contains("2026.10.22") })
  #expect(blocks.contains { $0.kind == .rule })
  #expect(blocks.last?.kind == .quote)
}

@Test func markdownAnalysisRetainsInlineFormattingAndOrdinaryDocumentLines() {
  let blocks = AnalysisDocument.blocks(
    "## 主要结论\n\n**预算**已确认。\n下一步与负责人核对。\n\n- 周五前回复\n- 保留原链接 https://example.com")
  #expect(blocks.map(\.kind) == [.heading, .paragraph, .listItem, .listItem])
  #expect(blocks[1].text == "**预算**已确认。\n下一步与负责人核对。")
  #expect(blocks.last?.text.contains("https://example.com") == true)
}
