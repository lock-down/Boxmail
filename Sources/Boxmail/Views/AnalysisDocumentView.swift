import AppKit
import BoxmailCore
import SwiftUI

struct AnalysisDocumentView: View {
  let text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(AnalysisDocument.blocks(text)) { block in
        switch block.kind {
        case .heading:
          Text(inline(block.text)).font(.system(size: 14, weight: .semibold))
            .padding(.top, block.id == 0 ? 0 : 8)
        case .listItem:
          HStack(alignment: .top, spacing: 10) {
            Text(block.marker).font(.system(size: 12, weight: .medium)).foregroundStyle(
              Palette.blue
            )
            .frame(minWidth: 20, alignment: .leading)
            paragraph(block.text)
          }
        case .paragraph:
          paragraph(block.text)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard MailHTMLDocument.externalLink(url) else { return .discarded }
          NSWorkspace.shared.open(url)
          return .handled
        })
  }
  private func paragraph(_ value: String) -> some View {
    Text(inline(value)).font(.system(size: 13)).lineSpacing(6)
      .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
  }
  private func inline(_ value: String) -> AttributedString {
    (try? AttributedString(
      markdown: value,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(value)
  }
}
