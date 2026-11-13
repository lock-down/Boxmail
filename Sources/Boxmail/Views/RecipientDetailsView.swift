import SwiftUI

struct RecipientDetailsView: View {
  let fields: [RecipientField]
  @ViewState<Bool> private var expanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(to: String, cc: String, bcc: String = "") {
    self.init(fields: [.init(kind: .to, value: to), .init(kind: .cc, value: cc), .init(kind: .bcc, value: bcc)])
  }
  init(fields: [RecipientField]) { self.fields = fields.filter { !$0.value.isEmpty } }
  private var summary: String {
    guard let first = fields.first else { return "发送至" }
    return "\(first.kind == .to ? "发送至" : first.title) \(first.value)"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        expanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Text(summary).lineLimit(1).truncationMode(.tail)
          Image(systemName: "chevron.down").font(.system(size: 9))
            .rotationEffect(.degrees(expanded ? -180 : 0)).accessibilityHidden(true)
        }.font(.system(size: 11)).foregroundStyle(Palette.muted).controlLabel(size: .compact)
      }.buttonStyle(ControlFeedback()).controlFocus()
        .accessibilityValue(expanded ? "已展开" : "已收起")
        .help(expanded ? "收起收件信息" : "展开完整收件信息")
      if expanded {
        RecipientAddressList(fields: fields)
          .fixedSize(horizontal: false, vertical: true)
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
          .transition(UIMotion.reveal(reduceMotion))
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: expanded)
  }
}
