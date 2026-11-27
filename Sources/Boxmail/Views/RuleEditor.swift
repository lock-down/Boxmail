import BoxmailCore
import SwiftUI

struct RuleEditor: View {
  @Bindable var store: MailStore
  @Bindable var workspace: RuleWorkspaceStore
  let initial: MailRule
  @ViewState private var rule: MailRule
  @Environment(\.dismiss) private var dismiss
  init(store: MailStore, workspace: RuleWorkspaceStore, initial: MailRule) {
    self.store = store
    self.workspace = workspace
    self.initial = initial
    _rule = ViewState(initialValue: initial)
  }
  var body: some View {
    VStack(spacing: 0) {
      WorkspaceHeader(
        title: initial.id.isEmpty ? "新建整理规则" : "编辑整理规则",
        subtitle: "设置条件和动作，保存后预览匹配邮件"
      ) { EmptyView() }
      .padding(.horizontal, 24).padding(.vertical, 16).background(Palette.paper)
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SectionCard(title: "规则说明", contentSpacing: 10, inset: 16) {
            HStack(alignment: .top, spacing: 12) {
              WorkflowField(title: "名称") {
                WorkflowTextInput(label: "规则名称", placeholder: "整理周报", text: $rule.name)
              }
              WorkflowField(title: "处理意图") {
                WorkflowTextInput(label: "处理意图", placeholder: "规则用途", text: $rule.intent)
              }
            }
          }
          SectionCard(title: "匹配条件", contentSpacing: 10, inset: 16) {
            MailQueryEditor(
              query: $rule.query, accounts: store.accounts, categories: store.categories)
          }
          SectionCard(title: "邮件动作", contentSpacing: 10, inset: 16) {
            WrappingFlowLayout(spacing: 16) {
              WorkflowSelection(
                title: "分类动作",
                selection: Binding(
                  get: { rule.actions.category ?? "" },
                  set: { rule.actions.category = $0.isEmpty ? nil : $0 }),
                options: [("", "保持分类")] + store.categories.map { ($0.name, $0.name) }).frame(width: 170)
              actionToggle("添加星标", value: $rule.actions.starred).frame(height: SettingsFormLayout.controlHeight)
              Toggle(
                "标记已读",
                isOn: Binding(
                  get: { rule.actions.unread == false },
                  set: { rule.actions.unread = $0 ? false : nil }))
                .frame(height: SettingsFormLayout.controlHeight)
              actionToggle("归档", value: $rule.actions.archive).frame(height: SettingsFormLayout.controlHeight)
            }
          }
          if rule.actions.includesAI {
            SectionCard(title: "旧 AI 动作", contentSpacing: 10, inset: 16) {
              Text(rule.actions.description).font(UIType.caption)
              ActionButton(title: "移除动作") {
                rule.actions.summary = nil
                rule.actions.attachments = nil
                rule.actions.followUp = nil
                rule.actions.reply = nil
              }
            }
          }
          SectionCard(title: "运行方式", contentSpacing: 10, inset: 16) {
            WrappingFlowLayout(spacing: 16) {
              Toggle("启用规则", isOn: $rule.enabled)
              Toggle("来信运行", isOn: $rule.automatic)
                .accessibilityHint("收到新邮件时自动运行")
                .disabled(rule.actions.includesAI)
            }
            Text("自动规则按创建顺序执行，修改仅对后续运行生效。")
              .font(UIType.small).foregroundStyle(Palette.muted)
          }
          if let error = workspace.error { WorkflowNotice(text: error, color: Palette.amber) }
        }.font(UIType.body).toggleStyle(CossToggleStyle()).padding(16).frame(maxWidth: 800)
          .frame(maxWidth: .infinity)
      }
      SettingsActionBar(
        primaryTitle: "保存规则",
        primaryDisabled: rule.name.trimmingCharacters(in: .whitespaces).isEmpty
          || rule.actions.description.isEmpty,
        cancel: { dismiss() }, primary: { Task { if await workspace.save(rule) { dismiss() } } }
      ) { EmptyView() }
    }.background(Palette.canvas)
  }
  private func actionToggle(_ title: String, value: Binding<Bool?>) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { value.wrappedValue == true }, set: { value.wrappedValue = $0 ? true : nil }))
  }
}
