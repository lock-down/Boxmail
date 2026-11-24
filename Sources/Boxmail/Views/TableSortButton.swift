import SwiftUI

/// The table owns column width; feedback stays around the title and its reserved arrow slot.
struct TableSortButton: View {
  let title: String
  let selected: Bool
  let ascending: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Text(title)
        RemixIcon(ascending ? .arrowUpLine : .arrowDownLine, size: 10)
          .frame(width: 12).opacity(selected ? 1 : 0)
      }.font(UIType.small).foregroundStyle(Palette.muted)
        .controlLabel(size: .compact)
        .fixedSize(horizontal: true, vertical: false)
    }.buttonStyle(ControlFeedback()).controlFocus()
      .alignmentGuide(.leading) { $0[.leading] + UIControlSize.compact.horizontalInset }
      .accessibilityLabel("按\(title)排序")
      .accessibilityValue(selected ? ascending ? "升序" : "降序" : "未排序")
      .cossTooltip("按\(title)\(selected && ascending ? "降序" : "升序")排序")
  }
}
