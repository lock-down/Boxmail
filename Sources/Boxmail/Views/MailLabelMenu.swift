import BoxmailCore

@MainActor @CossMenuItems
func mailLabelMenu(store: MailStore, messages: [MailMessage]) -> [CossMenuItem] {
  let membership = messages.map { Set(store.labels(for: $0).map(\.id)) }
  if membership.count == 1, let labels = membership.first {
    for label in store.mailLabels {
      CossMenuItem.command(label.name, mark: .checkbox(labels.contains(label.id)),
        enabled: !store.busy.contains("labels")) {
        store.setLabel(label, on: messages, add: !labels.contains(label.id))
      }
    }
  } else {
    CossMenuItem.submenu("添加标签", items: store.mailLabels.map { label in
      .command(label.name, enabled: !membership.allSatisfy { $0.contains(label.id) }) {
        store.setLabel(label, on: messages, add: true)
      }
    })
    CossMenuItem.submenu("移除标签", items: store.mailLabels.filter { label in
      membership.contains { $0.contains(label.id) }
    }.map { label in
      .command(label.name) { store.setLabel(label, on: messages, add: false) }
    })
  }
  CossMenuItem.divider
  CossMenuItem.command("管理标签…", icon: .settings) { store.showLabelManager = true }
}
