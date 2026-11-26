import SwiftUI

struct IconButton: View {
  let icon: AppicaGlyph
  let help: String
  var color: Color = Palette.muted
  var size: CGFloat = UILayout.iconControl
  var selected = false
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      AppicaIcon(icon)
        .foregroundStyle(color)
        .contentTransition(reduceMotion ? .identity : .opacity)
        .frame(width: size, height: size)
        .background(
          selected ? Palette.accentSoft : .clear,
          in: RoundedRectangle(cornerRadius: UILayout.iconRadius, style: .continuous))
        .animation(UIMotion.feedback(reduceMotion), value: icon)
    }.buttonStyle(ControlFeedback(selected: selected, corner: UILayout.iconRadius))
      .controlFocus(corner: UILayout.iconRadius)
      .cossTooltip(help).accessibilityLabel(help)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct IconMenu: View {
  let icon: AppicaGlyph
  let help: String
  var size: CGFloat = UILayout.iconControl
  @CossMenuItems var content: () -> [CossMenuItem]

  var body: some View {
    CossMenu(title: help, items: content) {
      AppicaIcon(icon)
        .foregroundStyle(Palette.muted).frame(width: size, height: size)
    }.cossTooltip(help)
  }
}
