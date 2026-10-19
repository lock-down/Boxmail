import SwiftUI

struct AIResultDisclosure<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  var copyHelp = "复制理解结果"
  var copy: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Button { isExpanded.toggle() } label: {
          HStack(spacing: 9) {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .foregroundStyle(Palette.muted).frame(width: 12).accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }.foregroundStyle(Palette.ink).padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(ControlFeedback()).focused($focused)
          .accessibilityLabel(title).accessibilityValue(isExpanded ? "已展开" : "已收起").help(title)
          .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Palette.accent : .clear, lineWidth: 2))
        if let copy { CopyButton(help: copyHelp, action: copy).padding(.trailing, 6) }
      }
      if isExpanded {
        content().padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .transition(UIMotion.reveal(reduceMotion))
      }
    }.overlay(alignment: .top) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
      .animation(UIMotion.disclosure(reduceMotion), value: isExpanded)
  }
}
