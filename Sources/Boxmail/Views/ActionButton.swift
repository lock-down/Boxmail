import SwiftUI

/// Text actions share metrics and feedback; emphasis is independent of their purpose.
struct ActionButton: View {
  let title: String
  var icon: AppicaGlyph? = nil
  var color: Color = Palette.ink
  var emphasis: ButtonEmphasis = .plain
  var size: UIControlSize = .regular
  var width: CGFloat? = nil
  var minimumWidth: CGFloat? = nil
  var fillsWidth = false
  var alignment: Alignment = .center
  var help: String? = nil
  var role: ButtonRole? = nil
  let action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
      ActionLabel(title: title, icon: icon, font: size.font)
        .foregroundStyle(emphasis.isSolid ? Palette.primaryForeground : color)
        .controlLabel(size: size, horizontalInset: emphasis == .plain ? nil : 16,
          fillsWidth: fillsWidth, alignment: alignment)
        .frame(minWidth: minimumWidth, alignment: alignment)
        .frame(width: width, height: size.height, alignment: alignment)
    }.buttonStyle(ControlFeedback(selected: emphasis == .tinted, emphasis: emphasis)).controlFocus()
      .cossTooltip(help ?? "").accessibilityLabel(help ?? title)
  }
}

struct ActionLabel: View {
  let title: String
  var icon: AppicaGlyph? = nil
  var font: Font = UIControlSize.regular.font

  var body: some View {
    HStack(spacing: 8) {
      if let icon {
        AppicaIcon(icon)
          .frame(width: 16).accessibilityHidden(true)
      }
      Text(title).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }.font(font)
  }
}
