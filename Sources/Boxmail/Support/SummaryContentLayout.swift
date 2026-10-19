import SwiftUI

enum SummarySection { case overview, followUp, keyInfo }
struct SummarySectionKey: LayoutValueKey {
  static let defaultValue = SummarySection.overview
}

/// Measure each section at its final width so long text determines the card's height.
struct SummaryContentLayout: Layout {
  private let gap: CGFloat = 24

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 840
    return arrangement(subviews, width: max(1, width)).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = arrangement(subviews, width: bounds.width)
    for (index, frame) in result.frames.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }

  private func arrangement(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
    var frames = Array(repeating: CGRect.zero, count: subviews.count)
    let overview = subviews.firstIndex { $0[SummarySectionKey.self] == .overview }
    let followUp = subviews.firstIndex { $0[SummarySectionKey.self] == .followUp }
    let keyInfo = subviews.firstIndex { $0[SummarySectionKey.self] == .keyInfo }

    func place(_ index: Int?, x: CGFloat, y: CGFloat = 0, width: CGFloat) {
      guard let index else { return }
      let height = ceil(subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
      frames[index] = CGRect(x: x, y: y, width: width, height: height)
    }

    if width >= 1120, keyInfo != nil {
      let available = width - gap * 2
      let overviewWidth = available * 0.44
      let followUpWidth = available * 0.32
      place(overview, x: 0, width: overviewWidth)
      place(followUp, x: overviewWidth + gap, width: followUpWidth)
      place(keyInfo, x: overviewWidth + followUpWidth + gap * 2, width: available - overviewWidth - followUpWidth)
    } else if width >= 720 {
      let available = width - gap
      let overviewWidth = available * 0.52
      place(overview, x: 0, width: overviewWidth)
      place(followUp, x: overviewWidth + gap, width: available - overviewWidth)
      let informationY = overview.map { frames[$0].maxY + gap } ?? 0
      place(keyInfo, x: 0, y: informationY, width: overviewWidth)
    } else {
      var y: CGFloat = 0
      for index in subviews.indices {
        place(index, x: 0, y: y, width: width)
        y = frames[index].maxY + gap
      }
    }
    return (frames, CGSize(width: width, height: frames.map(\.maxY).max() ?? 0))
  }
}
