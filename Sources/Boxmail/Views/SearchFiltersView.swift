import BoxmailCore
import SwiftUI

struct SearchFiltersView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<String> private var keywords = ""
  @ViewState<String> private var sender = ""
  @ViewState<String> private var recipient = ""
  @ViewState<String> private var after = ""
  @ViewState<String> private var before = ""
  @ViewState<String> private var account = "current"
  @ViewState<String> private var folder = ""
  @ViewState<String> private var read = ""
  @ViewState<Bool> private var attachments = false
  @ViewState<[SearchCondition]> private var additional = []
  @ViewState<String?> private var error = nil
  @ViewState<Bool> private var working = false
  @ViewState<String?> private var choosingDate = nil

  private let folderStatuses = Set(["sent", "drafts", "archive", "trash"])
  private var statusSelection: Binding<String> {
    Binding(get: { read }, set: { value in
      let previous = read
      read = value
      if folderStatuses.contains(value) { folder = value }
      else if folderStatuses.contains(previous) && folder == previous { folder = "" }
    })
  }
  private var folderSelection: Binding<String> {
    Binding(get: { folder }, set: { value in
      folder = value
      if read.isEmpty || folderStatuses.contains(read) { read = folderStatuses.contains(value) ? value : "" }
    })
  }
  var body: some View {
    Group {
      if let choosingDate {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            WorkflowAction(title: "返回", icon: "chevron.left") { self.choosingDate = nil }
              .keyboardShortcut(.cancelAction)
            Text(choosingDate == "after" ? "选择起始日期" : "选择截止日期").font(UIType.heading)
            Spacer()
          }
          Text(choosingDate == "after" ? "搜索范围包含所选当天" : "搜索范围不包含所选当天")
            .font(UIType.caption).foregroundStyle(Palette.muted)
          SearchCalendarPanel(title: choosingDate == "after" ? "起始日期" : "截止日期",
            selection: choosingDate == "after" ? $after : $before) { self.choosingDate = nil }
            .frame(maxWidth: .infinity)
        }.padding(24).frame(width: 360).background(Palette.paper)
      } else { filtersForm }
    }.tint(Palette.blue)
      .onSubmit { if !working && choosingDate == nil { apply() } }
      .onChange(of: after) { _, _ in error = nil }
      .onChange(of: before) { _, _ in error = nil }
      .task { await populate() }
  }
  private var filtersForm: some View {
    VStack(alignment: .leading, spacing: 16) {
      WorkflowPanelHeader(title: "搜索条件", subtitle: "所有条件同时满足，仅搜索本机已缓存的邮件", closeLabel: "关闭搜索条件") { dismiss() }
      VStack(spacing: 14) {
        field("关键词", text: $keywords, placeholder: "正文、附件名称或 AI 结果")
        HStack(alignment: .top, spacing: 16) {
          field("发件人", text: $sender, placeholder: "姓名或邮箱")
          field("收件人", text: $recipient, placeholder: "含抄送与密送")
        }
      }
      Divider().overlay(Palette.softBorder)
      VStack(spacing: 14) {
        HStack(alignment: .top, spacing: 16) {
          WorkflowField(title: "账户") {
            WorkflowSelection(title: "搜索账户", selection: $account,
              options: [("current", "当前账户"), ("all", "全部账户")] + store.accounts.map { ($0.email, $0.email) })
          }
          WorkflowField(title: "文件夹") {
            WorkflowSelection(title: "搜索文件夹", selection: folderSelection,
              options: [("", "全部文件夹")] + [MailDestination.inbox, .sent, .archive, .trash, .drafts].map { ($0.rawValue, $0.title) } + [("spam", "垃圾邮件")])
          }
        }
        HStack(alignment: .top, spacing: 16) {
          WorkflowField(title: "起始日期（含当天）") { SearchDatePicker(title: "选择起始日期", value: $after) { choosingDate = "after" } }
          WorkflowField(title: "截止日期（不含当天）") { SearchDatePicker(title: "选择截止日期", value: $before) { choosingDate = "before" } }
        }
        HStack {
          Text("状态").font(UIType.caption).foregroundStyle(Palette.muted)
          WorkflowSelection(title: "搜索邮件状态", selection: statusSelection,
            options: [("", "全部状态"), ("unread", "未读"), ("read", "已读"), ("starred", "星标"),
              ("sent", "已发送"), ("drafts", "草稿箱"), ("archive", "已归档"), ("trash", "已删除")])
            .frame(width: 142)
          Spacer()
          Toggle("仅有附件", isOn: $attachments).toggleStyle(.checkbox).font(UIType.caption)
        }.padding(.top, 2)
      }
      if !additional.isEmpty {
        Text("保留的条件：" + additional.map { "\($0.field):\($0.value)" }.joined(separator: " · "))
          .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(2)
          .help(additional.map { "\($0.field):\($0.value)" }.joined(separator: " "))
      }
      if let error { WorkflowNotice(text: error, icon: "exclamationmark.circle", color: Palette.amber) }
      Divider().overlay(Palette.softBorder)
      HStack {
        WorkflowAction(title: "清除搜索", icon: "arrow.uturn.backward") { store.search = ""; store.searchAllAccounts = false; dismiss() }
        Spacer()
        if working { ProgressView().controlSize(.small) }
        WorkflowAction(title: working ? "正在搜索…" : "搜索邮件", icon: "magnifyingglass", color: Palette.blue) { apply() }
          .disabled(working)
      }
    }.padding(24).frame(width: 520).background(Palette.paper).tint(Palette.blue)
  }
  private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
    WorkflowField(title: title) {
      WorkflowTextInput(label: "搜索\(title)", placeholder: placeholder, text: text)
    }
  }
  private func populate() async {
    do {
      var query = URLComponents(); query.queryItems = [URLQueryItem(name: "q", value: store.search)]
      let parsed: ParsedSearch = try await BackendService.shared.request("/search/parse?" + (query.percentEncodedQuery ?? ""))
      keywords = parsed.terms.map(SearchQueryBuilder.quoted).joined(separator: " ")
      for item in parsed.conditions {
        switch item.field {
        case "from": sender = item.value
        case "to": recipient = item.value
        case "after": after = item.value
        case "before": before = item.value
        case "account": account = item.value
        case "folder": folder = item.value
        case "is": read = item.value
        case "has": attachments = true
        default: additional.append(item)
        }
      }
      if read.isEmpty && folderStatuses.contains(folder) { read = folder }
      if account == "current" && store.searchAllAccounts { account = "all" }
    } catch { self.error = error.localizedDescription; keywords = store.search }
  }
  private func apply() {
    var conditions = [("from", sender), ("to", recipient), ("after", after), ("before", before), ("folder", folder), ("is", folderStatuses.contains(read) ? "" : read)]
    if attachments { conditions.append(("has", "attachment")) }
    if account != "current" && account != "all" { conditions.append(("account", account)) }
    conditions += additional.map { ($0.field, $0.value) }
    let candidate = [keywords.trimmingCharacters(in: .whitespacesAndNewlines), SearchQueryBuilder.make(terms: [], conditions: conditions)]
      .filter { !$0.isEmpty }.joined(separator: " ")
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "q", value: candidate)]
        let _: ParsedSearch = try await BackendService.shared.request("/search/parse?" + (query.percentEncodedQuery ?? ""))
        store.searchAllAccounts = account == "all"; store.search = candidate; store.filter = "全部"; dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}
