import BoxmailCore
import SwiftUI

struct AttachmentIcon: View {
  let attachment: MailAttachment
  var size: CGFloat = 25
  private var icon: RemixGlyph {
    switch attachment.kind {
    case .image: .imageLine
    case .pdf: .filePdfLine
    case .spreadsheet: .fileExcelLine
    case .presentation: .filePptLine
    case .word, .text: .fileTextLine
    case .archive: .fileZipLine
    case .other: .fileLine
    }
  }
  private var color: Color {
    switch attachment.kind {
    case .pdf: return Color(hex: 0xC23C41)
    case .spreadsheet: return Palette.success
    case .word: return Palette.accent
    case .presentation: return Color(hex: 0xA87416)
    case .image: return Color(hex: 0x7962AF)
    case .archive: return Palette.muted
    case .text, .other: return Palette.muted
    }
  }
  var body: some View {
    RemixIcon(icon, size: size)
      .foregroundStyle(color).frame(width: size + 5, height: size + 9)
      .accessibilityHidden(true)
  }
}
