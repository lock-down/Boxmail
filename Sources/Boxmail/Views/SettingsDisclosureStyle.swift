import SwiftUI

struct SettingsDisclosureStyle: DisclosureGroupStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(UIMotion.disclosure(reduceMotion)) { configuration.isExpanded.toggle() }
      } label: {
        HStack(spacing: 8) {
          configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
          Spacer(minLength: 0)
          AppicaIcon(.chevronDown, size: UILayout.smallIconSize)
            .foregroundStyle(Palette.muted).frame(width: 14)
            .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0)).accessibilityHidden(true)
        }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
          .contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
      }.buttonStyle(ControlFeedback(showsInteractionBackground: false))
        .controlFocus(corner: UILayout.controlRadius)
        .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
      if configuration.isExpanded { configuration.content }
    }
  }
}
