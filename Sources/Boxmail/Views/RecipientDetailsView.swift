import SwiftUI

struct RecipientDetailsView: View {
  let to: String
  let cc: String
  @ViewState<Bool> private var expanded = false
  @ViewState<CGFloat> private var contentHeight = 44
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        expanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Text("发送至 \(to)").lineLimit(1).truncationMode(.tail)
          Image(systemName: "chevron.down").font(.system(size: 9))
            .rotationEffect(.degrees(expanded ? -180 : 0)).accessibilityHidden(true)
        }.font(.system(size: 11)).foregroundStyle(Palette.muted).contentShape(Rectangle())
      }.buttonStyle(ControlFeedback()).controlFocus()
        .accessibilityValue(expanded ? "已展开" : "已收起")
        .help(expanded ? "收起收件人" : "展开完整收件人与抄送")
      if expanded {
        OverlayScrollView(persistentIndicators: true) {
          VStack(alignment: .leading, spacing: 12) {
            addresses("收件人", to)
            if !cc.isEmpty { addresses("抄送", cc) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(
              GeometryReader { geometry in
                Color.clear.preference(key: RecipientHeight.self, value: geometry.size.height)
              })
        }.frame(height: min(120, max(36, contentHeight)))
          .onPreferenceChange(RecipientHeight.self) { contentHeight = $0 }
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
          .accessibilityLabel("收件人与抄送名单")
          .transition(UIMotion.reveal(reduceMotion))
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: expanded)
  }
  private func addresses(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
      Text(value).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private enum RecipientHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
