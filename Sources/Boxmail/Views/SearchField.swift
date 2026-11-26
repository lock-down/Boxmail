import SwiftUI

struct SearchField: View {
  let placeholder: String
  @Binding var text: String
  var focusRequest = 0
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 8) {
      AppicaIcon(.search, size: UILayout.compactIconSize)
        .foregroundStyle(focused ? Palette.accent : Palette.muted).accessibilityHidden(true)
      TextField("", text: $text).textFieldStyle(.plain).font(UIType.caption)
        .focused($focused).accessibilityLabel(placeholder)
        .overlay(alignment: .leading) {
          if text.isEmpty {
            Text(placeholder).font(UIType.caption).foregroundStyle(Palette.muted).lineLimit(1)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      if !text.isEmpty {
        IconButton(icon: .circleXFilled, help: "清除搜索", size: 24) { text = "" }
          .transition(.opacity)
      }
    }.padding(.leading, 10).padding(.trailing, text.isEmpty ? 10 : 4).frame(height: 34)
      .controlFieldSurface(focused: focused)
      .animation(UIMotion.feedback(reduceMotion), value: focused)
      .animation(UIMotion.feedback(reduceMotion), value: text.isEmpty)
      .onChange(of: focusRequest) { _, _ in focused = true }
  }
}
