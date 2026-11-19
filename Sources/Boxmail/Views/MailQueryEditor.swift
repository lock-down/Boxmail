import BoxmailCore
import SwiftUI

/// Structured mail conditions used by the rule editor.
struct MailQueryEditor: View {
  @Binding var query: MailQuery
  let accounts: [MailAccount]
  let categories: [MailCategory]
  var spacing: CGFloat = 12

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      WorkflowField(title: "搜索条件") {
        WorkflowTextInput(
          label: "搜索条件", placeholder: "关键词、发件人或日期条件", text: $query.query, font: UIType.caption)
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: spacing) {
          accountField.frame(minWidth: 150)
          folderField.frame(minWidth: 100)
          statusField.frame(minWidth: 100)
          categoryField.frame(minWidth: 120)
        }
        VStack(spacing: spacing) {
          HStack(alignment: .top, spacing: spacing) { accountField; folderField }
          HStack(alignment: .top, spacing: spacing) { statusField; categoryField }
        }
      }
      DisclosureGroup("搜索语法") {
        Text("支持 from:、to:、after:、before:、is:、has:、folder:、category:。可用 folder: 限定搜索文件夹。")
          .font(UIType.small).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top, 8)
      }.disclosureGroupStyle(SettingsDisclosureStyle())
    }
  }

  private var accountField: some View {
    WorkflowField(title: "账户") {
      WorkflowSelection(title: "账户范围", selection: account,
        options: [("", "所有账户")] + accounts.map { ($0.id, $0.email) })
    }
  }
  private var folderField: some View {
    WorkflowField(title: "文件夹") {
      WorkflowSelection(title: "文件夹", selection: $query.folder,
        options: [MailDestination.inbox, .sent, .archive, .trash, .spam, .starred].map { ($0.rawValue, $0.title) })
    }
  }
  private var statusField: some View {
    WorkflowField(title: "状态") {
      WorkflowSelection(title: "邮件状态", selection: $query.filter,
        options: ["全部", "未读", "有附件", "AI 已总结"].map { ($0, $0) })
    }
  }
  private var categoryField: some View {
    WorkflowField(title: "分类") {
      WorkflowSelection(title: "邮件分类", selection: category,
        options: [("", "全部分类")] + categories.map { ($0.name, $0.name) })
    }
  }

  private var account: Binding<String> {
    Binding(get: { query.accountId ?? "" }, set: { query.accountId = $0.isEmpty ? nil : $0 })
  }
  private var category: Binding<String> {
    Binding(get: { query.category ?? "" }, set: { query.category = $0.isEmpty ? nil : $0 })
  }
}
