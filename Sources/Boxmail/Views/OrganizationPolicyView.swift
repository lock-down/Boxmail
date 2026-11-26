import BoxmailCore
import SwiftUI

struct OrganizationPolicyView: View {
  @Bindable var store: MailStore
  let initialAccountID: String
  let saved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @ViewState private var accountID = ""
  @ViewState private var policy: MailOrganizationPolicy?
  @ViewState private var working = false
  @ViewState private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: "新邮件自动整理", subtitle: "", closeLabel: "关闭") { dismiss() }.padding(20)
        .disabled(working)
      CossSeparator()
      VStack(alignment: .leading, spacing: 16) {
        WorkflowSelection(title: "选择邮箱", selection: $accountID,
          options: [("", "选择邮箱")] + store.accounts.filter { !$0.isDemo }.map { ($0.id, $0.email) })
        if let policy {
          Text(policy.mode == "automatic" ? (policy.point == nil ? "等待连接邮箱以建立新信起点" : "已开启自动整理")
            : policy.mode == "manual" ? "仅手动整理" : "尚未选择").font(UIType.section)
          Text("开启后，此后收到的邮件主题和正文会提交给你配置的 AI 服务商，用于生成摘要和待办。匹配标签时也会提交发件人和启用的条件。费用按服务商计收。")
            .font(UIType.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        if let error { WorkflowNotice(text: error, color: Palette.destructive) }
        Spacer(minLength: 0)
      }.padding(20).disabled(working)
      SettingsActionBar(primaryTitle: policy?.mode == "automatic" ? "关闭自动整理" : "开启自动整理",
        isWorking: working, primaryDisabled: policy == nil, cancelDisabled: working, cancel: { dismiss() },
        primary: { update(policy?.mode == "automatic" ? "manual" : "automatic") }) {
        if policy?.mode == "undecided" {
          ActionButton(title: "仅手动整理", emphasis: .secondary) { update("manual") }
            .disabled(working)
        }
      }
    }.background(Palette.paper).frame(width: 490, height: 320)
      .interactiveDismissDisabled(working)
      .onAppear { accountID = initialAccountID }
      .task(id: accountID) {
        policy = nil; error = nil
        guard !accountID.isEmpty else { return }
        do {
          let response = try await store.organizationPolicy(for: accountID)
          if !Task.isCancelled { policy = response }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
  }

  private func update(_ mode: String) {
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        _ = try await store.saveOrganizationPolicy(["accountId": accountID, "mode": mode, "confirmed": true])
        saved()
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}
