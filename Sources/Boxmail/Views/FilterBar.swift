import SwiftUI

/// One moving selection connects related filters without animating the result list.
struct FilterBar: View {
  let values: [String]
  @Binding var selection: String
  var compact = false
  var onSelect: (String) -> Void = { _ in }
  @Namespace private var highlight
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 2) {
      ForEach(values, id: \.self) { value in
        Button {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
          onSelect(value)
        } label: {
          Text(value).font(.system(size: compact ? 11 : 12, weight: selection == value ? .semibold : .regular))
            .foregroundStyle(selection == value ? Palette.blue : Palette.muted)
            .padding(.horizontal, compact ? 10 : 12).frame(height: compact ? 28 : 32)
            .background {
              if selection == value {
                if reduceMotion {
                  RoundedRectangle(cornerRadius: 6).fill(Palette.paper)
                } else {
                  RoundedRectangle(cornerRadius: 6).fill(Palette.paper)
                    .matchedGeometryEffect(id: "selection", in: highlight)
                }
              }
            }.contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(ControlFeedback(selected: selection == value, corner: 6))
          .controlFocus(corner: 6)
          .accessibilityAddTraits(selection == value ? .isSelected : [])
      }
    }.padding(3).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 9))
      .fixedSize(horizontal: true, vertical: false)
  }
}
