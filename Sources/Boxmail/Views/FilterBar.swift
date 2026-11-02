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
  private var corner: CGFloat { compact ? UILayout.controlRadius : UILayout.selectionRadius }
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
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Palette.blueSoft)
                } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Palette.blueSoft)
                    .matchedGeometryEffect(id: "selection", in: highlight)
                }
              }
          }.contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }.buttonStyle(ControlFeedback(selected: selection == value, corner: corner))
          .controlFocus(corner: corner)
          .accessibilityAddTraits(selection == value ? .isSelected : [])
      }
    }.fixedSize(horizontal: !fillsWidth, vertical: false)
  }
}

struct SegmentedSelection: View {
  let title: String
  let values: [String]
  @Binding var selection: String
  @Namespace private var highlight
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(values, id: \.self) { value in
        Button {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
        } label: {
          Text(value).font(.system(size: 12, weight: selection == value ? .semibold : .regular))
            .foregroundStyle(selection == value ? Palette.ink : Palette.muted)
            .lineLimit(1).padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 32)
            .background {
              if selection == value {
                if reduceMotion {
                  selectedSurface
                } else {
                  selectedSurface.matchedGeometryEffect(id: "selection", in: highlight)
                }
              }
            }
            .contentShape(
              RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
        }.buttonStyle(ControlFeedback(selected: selection == value, corner: UILayout.controlRadius))
          .controlFocus(corner: UILayout.controlRadius)
          .accessibilityAddTraits(selection == value ? .isSelected : [])
      }
    }.padding(3)
      .background(
        Palette.sidebar,
        in: RoundedRectangle(cornerRadius: UILayout.selectionRadius, style: .continuous)
      )
      .accessibilityElement(children: .contain).accessibilityLabel(title)
  }

  private var selectedSurface: some View {
    RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous)
      .fill(Palette.paper).shadow(color: .black.opacity(0.07), radius: 2, x: 0, y: 1)
  }
}
