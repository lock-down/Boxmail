import SwiftUI

struct IconButton: View {
  let icon: String
  let help: String
  var color: Color = Palette.muted
  var size: CGFloat = UILayout.iconControl
  var selected = false
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: UILayout.iconSize, weight: .regular))
        .foregroundStyle(color)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        .symbolEffectsRemoved(reduceMotion)
        .frame(width: size, height: size)
        .background(
          selected ? Palette.blueSoft : .clear,
          in: RoundedRectangle(cornerRadius: UILayout.iconRadius, style: .continuous))
        .animation(UIMotion.feedback(reduceMotion), value: icon)
    }.buttonStyle(ControlFeedback(selected: selected, corner: UILayout.iconRadius))
      .controlFocus(corner: UILayout.iconRadius)
      .help(help).accessibilityLabel(help)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct IconMenu<Content: View>: View {
  let icon: String
  let help: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    Menu(content: content) {
      Label(help, systemImage: icon).labelStyle(.iconOnly)
        .font(.system(size: UILayout.iconSize, weight: .regular))
        .foregroundStyle(Palette.muted).frame(width: UILayout.iconControl, height: UILayout.iconControl)
        .contentShape(RoundedRectangle(cornerRadius: UILayout.iconRadius, style: .continuous))
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .frame(width: UILayout.iconControl, height: UILayout.iconControl)
      .help(help).accessibilityLabel(help)
  }
}
