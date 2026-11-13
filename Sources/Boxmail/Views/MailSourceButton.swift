import SwiftUI

/// Evidence links keep the date readable while long sender names yield to the reading width.
struct MailSourceButton: View {
  let sender: String
  let date: String
  let subject: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "envelope").font(.system(size: UILayout.iconSize))
          .frame(width: 16).accessibilityHidden(true)
        Text(sender).lineLimit(1).truncationMode(.middle)
        Text(displayTime(date)).font(UIType.small).monospacedDigit().fixedSize()
      }.font(UIType.caption).foregroundStyle(Palette.accent)
        .controlLabel(size: .compact)
    }.buttonStyle(ControlFeedback()).controlFocus()
      .help("\(sender) · \(subject)")
      .accessibilityLabel("依据邮件：\(sender)，\(displayTime(date))，\(subject)")
  }
}
