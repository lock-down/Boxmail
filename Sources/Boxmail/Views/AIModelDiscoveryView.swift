import BoxmailCore
import SwiftUI

struct AIModelDiscoveryView: View {
  let candidates: [AIModel]
  let existingIDs: Set<String>
  let add: ([AIModel]) -> Void
  @Environment(\.dismiss) private var dismiss
  @ViewState<Set<String>> private var selected = []
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("可用模型").font(UIType.title)
        Spacer()
        SettingsInlineAction(title: "全选", icon: "checkmark") { selected = Set(candidates.map(\.id)).subtracting(existingIDs) }
      }
      Text("选择要加入目录的模型。已有模型的名称和参数会保留。")
        .font(UIType.caption).foregroundStyle(Palette.muted)
      OverlayScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(candidates) { candidate in
            Toggle(isOn: Binding(get: { existingIDs.contains(candidate.id) || selected.contains(candidate.id) }, set: {
              if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
            })) {
              VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName).font(UIType.caption)
                if candidate.displayName != candidate.id { Text(candidate.id).font(UIType.small).foregroundStyle(Palette.muted) }
              }
            }.toggleStyle(.checkbox).disabled(existingIDs.contains(candidate.id))
          }
        }.padding(4)
      }.frame(height: 280)
      HStack {
        Text("\(selected.count) 个待添加").font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        ActionButton(title: "取消") { dismiss() }.keyboardShortcut(.cancelAction)
        ActionButton(title: "添加所选模型", kind: .primary) {
          add(candidates.filter { selected.contains($0.id) }); dismiss()
        }.disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 550).background(Palette.paper)
  }
}
