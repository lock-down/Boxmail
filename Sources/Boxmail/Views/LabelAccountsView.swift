import BoxmailCore
import SwiftUI

struct LabelAccountsView: View {
  @Bindable var store: MailStore
  let label: MailCategory
  @Environment(\.dismiss) private var dismiss
  @ViewState private var enabled: Set<String> = []
  @ViewState private var pending: Set<String> = []
  @ViewState private var loaded = false
  @ViewState private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: "选择启用的邮箱", subtitle: label.name, closeLabel: "关闭") { dismiss() }.padding(20)
      CossSeparator()
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("所选邮箱整理邮件时，会使用此标签的匹配条件。").font(UIType.caption).foregroundStyle(Palette.muted)
          if let error { WorkflowNotice(text: error, color: Palette.destructive) }
          if loaded {
            ForEach(store.accounts) { account in
              Toggle(account.email, isOn: Binding(get: { enabled.contains(account.id) }, set: {
                change(account.id, enabled: $0)
              })).toggleStyle(CossToggleStyle(isSwitch: true)).disabled(pending.contains(account.id))
            }
          } else if error == nil {
            CossSpinner().accessibilityLabel("正在读取邮箱设置")
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
      }
    }.frame(width: 440, height: 300).background(Palette.paper)
      .task {
        do {
          for account in store.accounts {
            let policy = try await store.organizationPolicy(for: account.id)
            if policy.labelRules[label.id] != nil { enabled.insert(account.id) }
          }
          loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
  }

  private func change(_ accountID: String, enabled value: Bool) {
    guard pending.insert(accountID).inserted else { return }
    Task {
      defer { pending.remove(accountID) }
      do {
        _ = try await store.saveOrganizationPolicy(["accountId": accountID, "labelId": label.id, "enabled": value])
        if value { enabled.insert(accountID) } else { enabled.remove(accountID) }
        error = nil
      } catch { self.error = error.localizedDescription }
    }
  }
}
