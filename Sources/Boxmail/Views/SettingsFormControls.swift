import SwiftUI

enum SettingsFormLayout {
  static let labelWidth: CGFloat = 88
  static let columnGap: CGFloat = 12
  static let controlHeight: CGFloat = UIControlSize.form.height
  static let menuWidth: CGFloat = 132
  static let portWidth: CGFloat = 72
  static let actionWidth: CGFloat = 112
  static let fieldWidth: CGFloat = 280
  static let formWidth: CGFloat = labelWidth + columnGap + fieldWidth + columnGap + actionWidth
}

struct SettingsFormLabel: View {
  let title: String
  var body: some View {
    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
      .frame(width: SettingsFormLayout.labelWidth, alignment: .leading)
  }
}

struct SettingsFieldRow: View {
  let title: String
  @Binding var text: String
  var placeholder = ""
  var body: some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      WorkflowTextInput(label: title, placeholder: placeholder, text: $text, font: UIType.caption)
        .frame(width: SettingsFormLayout.fieldWidth)
      Spacer(minLength: 0)
    }
  }
}

struct SettingsTransferRow<Action: View>: View {
  let title, detail: String
  let icon: AppicaGlyph
  let action: () -> Action
  init(
    title: String, detail: String, icon: AppicaGlyph, @ViewBuilder action: @escaping () -> Action
  ) {
    self.title = title
    self.detail = detail
    self.icon = icon
    self.action = action
  }
  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      AppicaIcon(icon, size: UILayout.iconSize).foregroundStyle(Palette.muted)
        .frame(width: 24).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(detail).font(UIType.small).foregroundStyle(Palette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
      action().fixedSize()
    }
  }
}

struct SettingsInlineAction: View {
  let title: String
  let icon: AppicaGlyph
  var color: Color = Palette.accent
  let action: () -> Void

  var body: some View {
    ActionButton(title: title, icon: icon, color: color, size: .form,
      width: SettingsFormLayout.actionWidth, alignment: .leading, action: action)
  }
}

private struct SettingsInputSurface: ViewModifier {
  @FocusState private var focused: Bool
  func body(content: Content) -> some View {
    content.textFieldStyle(.plain).font(UIType.caption).foregroundStyle(Palette.ink)
      .padding(.horizontal, 10).frame(height: SettingsFormLayout.controlHeight)
      .focused($focused)
      .controlFieldSurface(focused: focused)
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
