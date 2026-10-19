import BoxmailCore
import SwiftUI

struct AttachmentIcon: View {
  let attachment: MailAttachment
  var size: CGFloat = 25
  private var symbol: String {
    if attachment.isImage { return "photo" }
    if attachment.isPDF { return "doc.richtext" }
    if attachment.isSpreadsheet { return "tablecells" }
    return "doc.text"
  }
  var body: some View {
    Image(systemName: symbol).font(.system(size: size, weight: .regular))
      .foregroundStyle(Palette.blue).frame(width: size + 5, height: size + 9)
      .accessibilityHidden(true)
  }
}
