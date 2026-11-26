import BoxmailCore
import SwiftUI

struct AttachmentIcon: View {
  let attachment: MailAttachment
  var size: CGFloat = 28
  private var icon: AppicaGlyph {
    switch attachment.kind {
    case .image: .photo
    case .pdf: .fileTypePdf
    case .spreadsheet: .fileExcel
    case .presentation: .fileTypePpt
    case .word, .text: .fileText
    case .archive: .fileZip
    case .other: .file
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
    AppicaIcon(icon, size: size)
      .foregroundStyle(color).frame(width: size + 4, height: size + 8)
      .accessibilityHidden(true)
  }
}
