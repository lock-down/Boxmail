import BoxmailCore
import SwiftUI

struct AnalysisTableView: View {
  let table: AnalysisTable
  @ViewState private var availableWidth: CGFloat = 0
  private var columnWidth: CGFloat {
    max(144, (availableWidth - 2) / CGFloat(table.headers.count))
  }
  var body: some View {
    OverlayScrollView(.horizontal) {
      Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
        row(table.headers, header: true)
        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, values in row(values) }
      }.clipShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous).strokeBorder(Palette.softBorder, lineWidth: 1) }
    }.background {
      GeometryReader { geometry in
        Color.clear.onAppear { availableWidth = geometry.size.width }
          .onChange(of: geometry.size.width) { _, width in availableWidth = width }
      }
    }
  }
  private func row(_ values: [String], header: Bool = false) -> some View {
    GridRow(alignment: .top) {
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        Text(AITextStyle.inline(value)).font(.system(size: 13, weight: header ? .semibold : .regular))
          .lineSpacing(5).frame(width: columnWidth - 24, alignment: alignment(index)).padding(12)
          .frame(maxHeight: .infinity, alignment: .top).background(header ? Palette.chrome : Palette.paper)
          .overlay(alignment: .bottom) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
      }
    }
  }
  private func alignment(_ index: Int) -> Alignment {
    switch table.alignments[index] {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
}
