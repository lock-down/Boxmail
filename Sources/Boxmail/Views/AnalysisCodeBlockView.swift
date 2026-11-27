import SwiftUI

struct AnalysisCodeBlockView: View {
  let text: String
  let language: String
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(language.isEmpty ? "代码" : language).font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        CopyButton(help: "复制代码") { text }
      }.padding(.horizontal, 12).padding(.vertical, 4)
      CossSeparator()
      OverlayScrollView(.horizontal) {
        Text(verbatim: text).font(.system(size: 12, design: .monospaced)).lineSpacing(5)
          .fixedSize(horizontal: true, vertical: true).padding(16)
      }
    }.background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous))
  }
}
