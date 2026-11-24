import SwiftUI

struct SettingsSelectionGroup {
  let title: String
  let value: String
  let items: [CossMenuItem]
}

struct SettingsSelectionMenu: View {
  let model: String
  let effort: String
  let groups: [SettingsSelectionGroup]

  var body: some View {
    CossMenu(title: effort.isEmpty ? "模型" : "模型与思考等级",
      value: effort.isEmpty ? model : model + "，" + effort,
      emphasis: .secondary, prefersSelection: groups.count == 1) {
      if groups.count == 1, let group = groups.first {
        group.items
      } else {
        for group in groups {
          CossMenuItem.submenu(group.title, value: group.value, items: group.items)
        }
      }
    } trigger: {
      CossMenuLabel(title: model, detail: effort.isEmpty ? nil : effort, size: .form, fillsWidth: true)
    }
  }
}
