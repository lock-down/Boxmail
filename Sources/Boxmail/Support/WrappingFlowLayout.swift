import SwiftUI

struct WrappingFlowLayout: Layout {
  var spacing: CGFloat = 6
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + CGFloat(max(0, subviews.count - 1)) * spacing
    let width = max(1, proposal.width?.isFinite == true ? proposal.width! : ideal)
    return positions(subviews, width: width).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let layout = positions(subviews, width: bounds.width)
    for (index, item) in layout.items.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
        proposal: ProposedViewSize(item.size))
    }
  }
  private func positions(_ subviews: Subviews, width: CGFloat) -> (items: [CGRect], size: CGSize) {
    var items: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    for view in subviews {
      let ideal = view.sizeThatFits(.unspecified)
      let size = view.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
      if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
      items.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
      x += size.width + spacing; rowHeight = max(rowHeight, size.height)
    }
    return (items, CGSize(width: width, height: y + rowHeight))
  }
}
