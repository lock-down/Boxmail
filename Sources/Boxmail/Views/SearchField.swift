import SwiftUI

struct SearchField: View {
  let placeholder: String
  @Binding var text: String
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 13))
        .foregroundStyle(focused ? Palette.blue : Palette.muted).accessibilityHidden(true)
      TextField(placeholder, text: $text).textFieldStyle(.plain).font(UIType.caption)
        .focused($focused).accessibilityLabel(placeholder)
      if !text.isEmpty {
        IconButton(icon: "xmark.circle.fill", help: "清除搜索", size: 24) { text = "" }
          .transition(.opacity)
      }
    }.padding(.leading, 11).padding(.trailing, text.isEmpty ? 11 : 5).frame(height: 34)
      .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(focused ? Palette.blue.opacity(0.7) : Palette.softBorder, lineWidth: focused ? 1.5 : 1)
          .allowsHitTesting(false)
      }.animation(UIMotion.feedback(reduceMotion), value: focused)
      .animation(UIMotion.feedback(reduceMotion), value: text.isEmpty)
  }
}
