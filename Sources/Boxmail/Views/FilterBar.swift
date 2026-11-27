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
    EqualWidthSegments(fillsWidth: fillsWidth) {
      ForEach(values, id: \.self) { value in
        SelectionButton(title: value, selected: selection == value,
          size: compact ? .compact : .regular, fillsWidth: true,
          appearance: .segmented, highlight: highlight) {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
          onSelect(value)
        }
      }
    }.segmentedSurface().fixedSize(horizontal: !fillsWidth, vertical: false)
  }
}

struct SegmentedSelection: View {
  let title: String
  let values: [String]
  @Binding var selection: String
  @Namespace private var highlight
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    EqualWidthSegments(fillsWidth: true) {
      ForEach(values, id: \.self) { value in
        SelectionButton(title: value, selected: selection == value, fillsWidth: true,
          appearance: .segmented, highlight: highlight) {
          withAnimation(UIMotion.selection(reduceMotion)) { selection = value }
        }
      }
    }.segmentedSurface()
      .accessibilityElement(children: .contain).accessibilityLabel(title)
  }
}

private struct EqualWidthSegments: Layout {
  let fillsWidth: Bool
  private let spacing = UILayout.segmentInset

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let idealWidth = (sizes.map(\.width).max() ?? 0) * CGFloat(sizes.count) + gaps(for: sizes.count)
    let width = fillsWidth ? proposal.width ?? idealWidth : min(proposal.width ?? idealWidth, idealWidth)
    return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard !subviews.isEmpty else { return }
    let width = max(0, bounds.width - gaps(for: subviews.count)) / CGFloat(subviews.count)
    for (index, subview) in subviews.enumerated() {
      subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.midY),
        anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
    }
  }

  private func gaps(for count: Int) -> CGFloat {
    CGFloat(max(0, count - 1)) * spacing
  }
}

extension View {
  func segmentedSurface() -> some View {
    padding(UILayout.segmentInset)
      .background(Palette.sidebar,
        in: RoundedRectangle(cornerRadius: UILayout.segmentRadius, style: .continuous))
  }
}
