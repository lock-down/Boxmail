import SwiftUI

enum SettingsFormLayout {
  static let labelWidth: CGFloat = 88
  static let columnGap: CGFloat = 12
  static let controlHeight: CGFloat = 32
  static let menuWidth: CGFloat = 132
  static let portWidth: CGFloat = 72
  static let actionWidth: CGFloat = 112
  static let modelSelectorWidth: CGFloat = 252
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
  let action: () -> Void
  @ViewState<Bool> private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 12, weight: .medium))
        Text(title).underline(focused)
      }.font(.system(size: 12, weight: .medium))
        .foregroundStyle(enabled && (hovered || focused) ? Palette.accent : Palette.ink)
        .frame(width: SettingsFormLayout.actionWidth, height: SettingsFormLayout.controlHeight)
        .contentShape(Rectangle()).opacity(enabled ? 1 : 0.45)
    }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
      .accessibilityLabel(title)
  }
}

struct SettingsMenuPicker<Value: Hashable, Content: View>: View {
  let title: String
  @Binding var selection: Value
  @ViewBuilder var content: () -> Content
  var body: some View {
    Picker(title, selection: $selection, content: content)
      .pickerStyle(.menu).labelsHidden().controlSize(.large).font(UIType.caption)
      .frame(width: SettingsFormLayout.menuWidth, height: SettingsFormLayout.controlHeight)
  }
}

extension View {
  func settingsTextInput() -> some View {
    textFieldStyle(.roundedBorder).controlSize(.large).font(UIType.caption)
      .frame(height: SettingsFormLayout.controlHeight)
  }
}
