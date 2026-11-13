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
    HStack(spacing: 4) {
      ForEach(values, id: \.self) { value in
        SelectionButton(title: value, selected: selection == value,
          size: compact ? .compact : .regular, fillsWidth: fillsWidth, highlight: highlight) {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
          onSelect(value)
        }
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
    HStack(spacing: 4) {
      ForEach(values, id: \.self) { value in
        SelectionButton(title: value, selected: selection == value, fillsWidth: true,
          appearance: .segmented, highlight: highlight) {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
        }
      }
    }.padding(4)
      .background(
        Palette.sidebar,
        in: RoundedRectangle(cornerRadius: UILayout.segmentRadius, style: .continuous))
      .accessibilityElement(children: .contain).accessibilityLabel(title)
  }
}
