import SwiftUI

struct RecipientTextBodyView: View {
  let text: String
  let font: Font
  var lineSpacing: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(RecipientTextBlock.split(text).enumerated()), id: \.offset) { _, block in
        switch block {
        case .text(let value):
          Text(value).font(font).lineSpacing(lineSpacing).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        case .recipients(let fields):
          RecipientDetailsView(fields: fields)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
