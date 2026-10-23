import SwiftUI

enum SettingsFormLayout {
  static let labelWidth: CGFloat = 88
  static let columnGap: CGFloat = 12
  static let controlHeight: CGFloat = 34
  static let menuWidth: CGFloat = 132
  static let portWidth: CGFloat = 72
  static let actionWidth: CGFloat = 112
  static let modelSelectorWidth: CGFloat = 280
  static let textWidth: CGFloat = 360
  static let shortTextWidth: CGFloat = 280
  static let formWidth: CGFloat = labelWidth + columnGap + textWidth + columnGap + actionWidth
}

struct SettingsFormLabel: View {
  let title: String
  var body: some View {
    Text(title).font(UIType.caption).foregroundStyle(Palette.muted)
      .frame(width: SettingsFormLayout.labelWidth, alignment: .leading)
  }
}

struct SettingsInlineAction: View {
  let title: String
  let icon: String
  var color: Color = Palette.accent
  let action: () -> Void
  @ViewState<Bool> private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Image(systemName: icon).font(.system(size: 12, weight: .medium))
          .frame(width: 14).accessibilityHidden(true)
        Text(title).underline(focused).lineLimit(1).fixedSize()
      }.font(.system(size: 12, weight: .medium))
        .foregroundStyle(hovered || focused ? Palette.accent : color)
        .padding(.horizontal, 6)
        .frame(width: SettingsFormLayout.actionWidth, height: SettingsFormLayout.controlHeight, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(ControlFeedback(corner: 6)).focused($focused).onHover { hovered = $0 }
      .animation(UIMotion.feedback(reduceMotion), value: hovered)
      .accessibilityLabel(title)
  }
}

private struct SettingsInputSurface: ViewModifier {
  @FocusState private var focused: Bool
  func body(content: Content) -> some View {
    content.textFieldStyle(.plain).font(UIType.caption).foregroundStyle(Palette.ink)
      .padding(.horizontal, 10).frame(height: SettingsFormLayout.controlHeight)
      .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7)).focused($focused)
      .overlay(alignment: .bottom) {
        if focused { Rectangle().fill(Palette.blue).frame(height: 1).padding(.horizontal, 8) }
      }
  }
}

extension View {
  func settingsTextInput() -> some View { modifier(SettingsInputSurface()) }
  func inputPlaceholder(_ text: String, visible: Bool) -> some View {
    overlay(alignment: .leading) {
      if visible {
        Text(text).font(UIType.caption).foregroundStyle(Palette.muted).padding(.horizontal, 10)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
    }
  }
}
