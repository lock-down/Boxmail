import SwiftUI

/// Keep facts with their overview and give actions their own column when space allows.
struct SummaryContentLayout: Layout {
  private let gap: CGFloat = 24

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 840
    return arrangement(subviews, width: max(1, width)).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (index, frame) in arrangement(subviews, width: bounds.width).frames.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }

  private func arrangement(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
    let sideBySide = subviews.count == 2 && width >= 720
    let primaryWidth = (width - gap) * 0.53
    var frames: [CGRect] = []
    for index in subviews.indices {
      let columnWidth = sideBySide ? (index == 0 ? primaryWidth : width - primaryWidth - gap) : width
      let x = sideBySide && index > 0 ? primaryWidth + gap : 0
      let y = sideBySide ? 0 : frames.last.map { $0.maxY + gap } ?? 0
      let height = ceil(subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height)
      frames.append(CGRect(x: x, y: y, width: columnWidth, height: height))
    }
    return (frames, CGSize(width: width, height: frames.map(\.maxY).max() ?? 0))
  }
}
