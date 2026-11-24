import BoxmailCore
import SwiftUI

enum AITextStyle {
  static let body: Font = .system(size: 14)
  static func preview(_ value: String) -> AttributedString {
    let text = AnalysisDocument.blocks(value).compactMap { block -> String? in
      switch block.kind {
      case .heading, .rule, .table: return nil
      default: return block.text.replacingOccurrences(of: "\n", with: " ")
      }
    }.joined(separator: " ")
    let rendered = inline(text.isEmpty ? value : text)
    let end = rendered.characters.index(rendered.startIndex, offsetBy: 600, limitedBy: rendered.endIndex) ?? rendered.endIndex
    return AttributedString(rendered[..<end])
  }
  static func inline(_ value: String) -> AttributedString {
    var result = AnalysisDocument.inlineText(value)
    for run in result.runs {
      if run.inlinePresentationIntent?.contains(.code) == true {
        result[run.range].font = .system(size: 12, design: .monospaced)
        result[run.range].backgroundColor = Palette.accentSoft
      }
      if let url = run.link, !MailHTMLDocument.externalLink(url) { result[run.range].link = nil }
    }
    return result
  }
}
