import SwiftUI

/// One moving selection connects related filters without animating the result list.
struct FilterBar: View {
  let values: [String]
  @Binding var selection: String
  var compact = false
  var fillsWidth = false
  var onSelect: (String) -> Void = { _ in }
  @Namespace private var highlight
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: compact ? 4 : 6) {
      ForEach(values, id: \.self) { value in
        Button {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
          onSelect(value)
        } label: {
          Text(value).font(.system(size: compact ? 11 : 12, weight: selection == value ? .semibold : .regular))
            .foregroundStyle(selection == value ? Palette.blue : Palette.muted)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: compact ? 28 : 32)
            .background {
              if selection == value {
                if reduceMotion {
                  RoundedRectangle(cornerRadius: 7).fill(Palette.blueSoft)
                } else {
                  RoundedRectangle(cornerRadius: 7).fill(Palette.blueSoft)
                    .matchedGeometryEffect(id: "selection", in: highlight)
                }
              }
            }.contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(ControlFeedback(selected: selection == value))
          .controlFocus()
          .accessibilityAddTraits(selection == value ? .isSelected : [])
      }
    }.fixedSize(horizontal: !fillsWidth, vertical: false)
  }
}
