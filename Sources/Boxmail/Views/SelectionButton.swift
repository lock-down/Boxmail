import SwiftUI

/// Standalone choices and filter groups share the same control, including moving highlights.
struct SelectionButton: View {
  let title: String
  var icon: String? = nil
  var selected = false
  var size: UIControlSize = .regular
  var fillsWidth = false
  var appearance: Appearance = .tinted
  var surface: Color = .clear
  var highlight: Namespace.ID? = nil
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  enum Appearance { case tinted, segmented }

  var body: some View {
    Button(action: action) {
      ActionLabel(title: title, icon: icon, font: size.font)
        .foregroundStyle(selected ? appearance == .segmented ? Palette.ink : Palette.blue : Palette.muted)
        .controlLabel(size: size, fillsWidth: fillsWidth)
        .background {
          ZStack {
            shape.fill(surface)
            if selected {
              if let highlight, !reduceMotion {
                selectedSurface.matchedGeometryEffect(id: "selection", in: highlight)
              } else {
                selectedSurface
              }
            }
          }
        }
    }.buttonStyle(ControlFeedback(selected: selected)).controlFocus()
      .accessibilityAddTraits(selected ? .isSelected : [])
      .animation(UIMotion.selection(reduceMotion), value: selected)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous)
  }

  private var selectedSurface: some View {
    shape.fill(appearance == .segmented ? Palette.paper : Palette.blueSoft)
      .shadow(color: .black.opacity(appearance == .segmented ? 0.07 : 0), radius: 2, x: 0, y: 1)
  }
}
