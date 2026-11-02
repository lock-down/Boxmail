import SwiftUI

struct SettingsDisclosureStyle: DisclosureGroupStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(UIMotion.disclosure(reduceMotion)) { configuration.isExpanded.toggle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.muted).frame(width: 12)
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0)).accessibilityHidden(true)
          configuration.label.font(UIType.caption).foregroundStyle(Palette.ink)
          Spacer(minLength: 0)
        }.padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
          .contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
      }.buttonStyle(ControlFeedback(corner: UILayout.controlRadius))
        .controlFocus(corner: UILayout.controlRadius)
        .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
      if configuration.isExpanded { configuration.content }
    }
  }
}
