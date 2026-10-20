import BoxmailCore
import SwiftUI

struct AttachmentIcon: View {
  let attachment: MailAttachment
  var size: CGFloat = 25
  private var symbol: String {
    switch attachment.kind {
    case .image: return "photo"
    case .pdf: return "doc.richtext"
    case .spreadsheet: return "tablecells"
    case .presentation: return "rectangle.on.rectangle"
    case .word, .text: return "doc.text"
    case .other: return "doc"
    }
  }
  private var color: Color {
    switch attachment.kind {
    case .pdf: return Color(hex: 0xC23C41)
    case .spreadsheet: return Palette.success
    case .word: return Palette.blue
    case .presentation: return Color(hex: 0xA87416)
    case .image: return Color(hex: 0x7962AF)
    case .text, .other: return Palette.muted
    }
  }
  var body: some View {
    Image(systemName: symbol).font(.system(size: size, weight: .regular))
      .foregroundStyle(color).frame(width: size + 5, height: size + 9)
      .accessibilityHidden(true)
  }
}
