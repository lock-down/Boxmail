import AppKit
import BoxmailCore
import SwiftUI

enum AITextStyle {
  static let body: Font = .system(size: 13)
  static func preview(_ value: String) -> AttributedString {
    let excerpt = String(value.prefix(600))
    let text = AnalysisDocument.blocks(excerpt).compactMap { block -> String? in
      switch block.kind {
      case .heading, .rule, .table: return nil
      default: return block.text.replacingOccurrences(of: "\n", with: " ")
      }
    }.joined(separator: " ")
    return inline(text.isEmpty ? excerpt : text)
  }
  static func inline(_ value: String) -> AttributedString {
    var result = AnalysisDocument.inlineText(value)
    for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
      result[run.range].font = .system(size: 12, design: .monospaced)
      result[run.range].backgroundColor = Palette.blueSoft
    }
    return result
  }
}
struct AnalysisDocumentView: View {
  let text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(AnalysisDocument.blocks(text)) { block in
        switch block.kind {
        case .heading:
          Text(AITextStyle.inline(block.text)).font(.system(size: block.level == 1 ? 20 : block.level == 2 ? 16 : 14, weight: .semibold))
            .foregroundStyle(Palette.ink).lineSpacing(3).padding(.top, block.id == 0 ? 0 : 12)
        case .listItem:
          HStack(alignment: .top, spacing: 8) {
            if let checked = block.checked {
              Image(systemName: checked ? "checkmark.square.fill" : "square").font(.system(size: 12))
                .foregroundStyle(Palette.accent).frame(width: 20, height: 18).accessibilityLabel(checked ? "已完成" : "未完成")
            } else {
              Text(block.marker).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent).frame(minWidth: 20, alignment: .leading)
            }
            paragraph(block.text)
          }.padding(.leading, CGFloat(block.level) * 16)
        case .paragraph: paragraph(block.text)
        case .quote:
          HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Palette.blue.opacity(0.4)).frame(width: 1)
            paragraph(block.text).foregroundStyle(Palette.muted)
          }.fixedSize(horizontal: false, vertical: true).padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 6))
        case .code:
          VStack(alignment: .leading, spacing: 8) {
            if !block.language.isEmpty { Text(block.language).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
            OverlayScrollView(.horizontal) {
              Text(verbatim: block.text).font(.system(size: 12, design: .monospaced)).lineSpacing(4)
                .fixedSize(horizontal: true, vertical: true).padding(.bottom, 2)
            }
          }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 6))
        case .table: if let table = block.table { AnalysisTableView(table: table) }
        case .rule: Divider().overlay(Palette.border).padding(.vertical, 4)
        }
      }
    }.font(AITextStyle.body).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      .environment(\.openURL, OpenURLAction { url in
        guard MailHTMLDocument.externalLink(url) else { return .discarded }
        NSWorkspace.shared.open(url); return .handled
      })
  }
  private func paragraph(_ value: String) -> some View {
    Text(AITextStyle.inline(value)).font(AITextStyle.body).lineSpacing(6)
      .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
  }
}
private struct AnalysisTableView: View {
  let table: AnalysisTable
  var body: some View {
    OverlayScrollView(.horizontal) {
      Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
        row(table.headers, header: true)
        ForEach(Array(table.rows.enumerated()), id: \.offset) { index, values in row(values, shaded: index.isMultiple(of: 2)) }
      }.clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border)).padding(1)
    }
  }
  private func row(_ values: [String], header: Bool = false, shaded: Bool = false) -> some View {
    GridRow(alignment: .top) {
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        Text(AITextStyle.inline(value)).font(.system(size: 12, weight: header ? .semibold : .regular)).lineSpacing(4)
          .frame(width: table.headers.count <= 2 ? 230 : 170, alignment: alignment(index)).padding(10)
          .frame(maxHeight: .infinity, alignment: .top).background(header ? Palette.blueSoft : shaded ? Palette.canvas : .white)
          .overlay(Rectangle().stroke(Palette.softBorder, lineWidth: 0.5))
      }
    }
  }
  private func alignment(_ index: Int) -> Alignment {
    switch table.alignments[index] { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
  }
}
