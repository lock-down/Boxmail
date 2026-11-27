import BoxmailCore
import SwiftUI

struct SummaryFactsView: View {
  let facts: [KeyInfo]

  var body: some View {
    let groups = SummaryFactGroup.organize(facts)
    VStack(alignment: .leading, spacing: 8) {
      Text("关键信息").font(UIType.section).accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(groups) { group in
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(group.kind.rawValue).font(UIType.small).foregroundStyle(Palette.muted).frame(width: 70, alignment: .leading)
            if group.facts.isEmpty {
              Text("—").foregroundStyle(Palette.muted).accessibilityLabel("原文未提供")
            } else {
              Text(AITextStyle.inline(value(in: group))).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
          }.font(UIType.caption).padding(.vertical, 7).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
          if group.id != groups.last?.id { CossSeparator().padding(.leading, 10) }
        }
      }.background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous))
    }
  }

  private func value(in group: SummaryFactGroup) -> String {
    group.facts.map { fact in
      fact.label == group.kind.rawValue ? fact.value : "\(fact.label)：\(fact.value)"
    }.joined(separator: " · ")
  }
}
