import AppKit
import BoxmailCore
import SwiftUI

/// A shared reading surface for AI prose, including partial streamed Markdown.
struct AnalysisDocumentView: View {
  let blocks: [AnalysisBlock]

  init(text: String) { self.init(blocks: AnalysisDocument.blocks(text)) }
  init(blocks: [AnalysisBlock]) { self.blocks = blocks }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(blocks) { block in
        content(block).padding(.top, spacing(before: block, in: blocks))
      }
    }.font(AITextStyle.body).foregroundStyle(Palette.ink)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      .tint(Palette.accent)
      .environment(\.openURL, OpenURLAction { url in
        guard MailHTMLDocument.externalLink(url) else { return .discarded }
        NSWorkspace.shared.open(url); return .handled
      })
  }
  private func spacing(before block: AnalysisBlock, in blocks: [AnalysisBlock]) -> CGFloat {
    guard block.id > 0 else { return 0 }
    let previous = blocks[block.id - 1]
    if block.kind == .heading { return 26 }
    if previous.kind == .heading { return 10 }
    if block.kind == .listItem && previous.kind == .listItem { return 7 }
    return 16
  }
  @ViewBuilder private func content(_ block: AnalysisBlock) -> some View {
    switch block.kind {
    case .heading:
      Text(AITextStyle.inline(block.text))
        .font(.system(size: block.level == 1 ? 22 : block.level == 2 ? 18 : 15, weight: .semibold))
        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    case .listItem:
      HStack(alignment: .top, spacing: 10) {
        if let checked = block.checked {
          AppicaIcon(checked ? .squareCheckFilled : .square, size: UILayout.compactIconSize)
            .foregroundStyle(checked ? Palette.accent : Palette.muted).frame(width: 18, height: 20)
            .accessibilityRepresentation { Text(checked ? "已完成" : "未完成") }
        } else {
          Text(block.marker).font(.system(size: 13)).foregroundStyle(Palette.muted)
            .monospacedDigit().frame(minWidth: 18, alignment: .trailing).padding(.top, 1)
        }
        paragraph(block.text)
      }.padding(.leading, CGFloat(block.level) * 20)
    case .paragraph: paragraph(block.text)
    case .quote:
      HStack(alignment: .top, spacing: 14) {
        Rectangle().fill(Palette.border).frame(width: 1)
        paragraph(block.text).foregroundStyle(Palette.muted)
      }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
    case .code: AnalysisCodeBlockView(text: block.text, language: block.language)
    case .table: if let table = block.table { AnalysisTableView(table: table) }
    case .rule: CossSeparator().padding(.vertical, 6)
    }
  }
  private func paragraph(_ value: String) -> some View {
    Text(AITextStyle.inline(value)).font(AITextStyle.body).lineSpacing(6)
      .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
  }
}
