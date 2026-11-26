import SwiftUI

/// Evidence links keep the date readable while long sender names yield to the reading width.
struct MailSourceButton: View {
  let sender: String
  let date: String
  let subject: String
  var icon: AppicaGlyph = .mail
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        AppicaIcon(icon)
          .frame(width: 16).accessibilityHidden(true)
        Text(sender).lineLimit(1).truncationMode(.middle)
        if !date.isEmpty { Text(displayTime(date)).font(UIType.small).monospacedDigit().fixedSize() }
      }.font(UIType.caption).foregroundStyle(Palette.accent)
        .controlLabel(size: .compact)
    }.buttonStyle(ControlFeedback()).controlFocus()
      .cossTooltip(sender == subject ? subject : "\(sender) · \(subject)")
      .accessibilityLabel(date.isEmpty ? "\(icon == .paperclip ? "依据附件" : "依据邮件")：\(subject)"
        : "依据邮件：\(sender)，\(displayTime(date))，\(subject)")
  }
}
