import BoxmailCore
import SwiftUI

struct OrganizationMailPicker: View {
  @Bindable var store: MailStore
  let label: MailCategory?
  @Environment(\.dismiss) private var dismiss
  @ViewState private var accountID = ""
  @ViewState private var search = ""
  @ViewState private var offset = 0
  @ViewState private var page: CandidatePage?
  @ViewState private var selected: Set<String> = []
  @ViewState private var policy: MailOrganizationPolicy?
  @ViewState private var preview: Trial?
  @ViewState private var force = false
  @ViewState private var loading = false
  @ViewState private var submitting = false
  @ViewState private var error: String?

  private struct CandidatePage: Decodable {
    let messages: [Candidate]
    let nextOffset: Int?
  }

  private struct Candidate: Decodable, Identifiable {
    let id, subject, sender, date: String
  }

  private struct Trial: Decodable {
    let id: String
    let matches: [Match]

    struct Match: Decodable, Identifiable {
      let messageId, subject: String
      var id: String { messageId }
    }
  }

  private var title: String { label == nil ? "整理邮件" : "试用标签条件" }
  private var enabledLabelIDs: [String] {
    store.mailLabels.filter { $0.match != nil && policy?.labelRules[$0.id] != nil }.map(\.id).sorted()
  }
  private var sendsSender: Bool { label != nil || !enabledLabelIDs.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: title, subtitle: label?.name ?? "选择要整理的本机邮件", closeLabel: "关闭") { dismiss() }
        .padding(20).disabled(submitting)
      CossSeparator()
      if let preview { review(preview) } else { selection }
      SettingsActionBar(primaryTitle: preview == nil ? (label == nil ? "整理所选邮件" : "试用条件") : "应用标签",
        isWorking: submitting, primaryDisabled: accountID.isEmpty || selected.isEmpty || policy == nil || preview?.matches.isEmpty == true,
        cancelDisabled: submitting, cancel: { dismiss() }, primary: submit) {
        Text("已选 \(selected.count) 封").font(UIType.caption).foregroundStyle(Palette.muted)
      }
    }
    .background(Palette.paper)
    .workspaceSheet(.categories)
    .interactiveDismissDisabled(submitting)
    .onAppear { if !store.unifiedInbox { accountID = store.accountId } }
    .onChange(of: accountID) { _, _ in
      selected = []; policy = nil; offset = 0; page = nil
    }
    .onChange(of: search) { _, _ in offset = 0; page = nil }
    .task(id: accountID) {
      let account = accountID
      guard !account.isEmpty else { return }
      do {
        let response = try await store.organizationPolicy(for: account)
        if !Task.isCancelled && account == accountID { policy = response }
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    .task(id: store.organizationPath("candidates", accountID: accountID, query: search, offset: offset)) {
      guard !accountID.isEmpty else { return }
      let path = store.organizationPath("candidates", accountID: accountID, query: search, offset: offset)
      loading = true
      defer { if !Task.isCancelled { loading = false } }
      do {
        try await Task.sleep(for: .milliseconds(180))
        let result: CandidatePage = try await store.backend.request(path)
        if !Task.isCancelled { page = result; error = nil }
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }

  private var selection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        WorkflowSelection(title: "来源账户", selection: $accountID,
          options: [("", "选择邮箱")] + store.accounts.map { ($0.id, $0.email) })
          .frame(width: 240)
        WorkflowTextInput(label: "搜索已缓存的邮件", placeholder: "搜索邮件", text: $search)
      }
      if let error { WorkflowNotice(text: error, color: Palette.destructive) }
      if !accountID.isEmpty, policy != nil {
        let fields = sendsSender ? "发件人、主题、正文和匹配条件" : "主题和正文"
        Text("提交给已配置的 AI 服务商：\(fields)。附件留在本机。")
          .font(UIType.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
      WorkspaceListSurface {
        EmptyView()
      } content: {
        if loading && page == nil {
          CossSpinner().padding(16).accessibilityLabel("正在搜索")
        } else if let page, page.messages.isEmpty {
          Text("没有符合条件的邮件").font(UIType.caption).foregroundStyle(Palette.muted).padding(16)
        }
        VStack(alignment: .leading, spacing: 0) {
          ForEach(page?.messages ?? []) { mail in
            Toggle(isOn: Binding(get: { selected.contains(mail.id) }, set: { checked in
              if checked { selected.insert(mail.id) } else { selected.remove(mail.id) }
            })) {
              VStack(alignment: .leading, spacing: 4) {
                Text(mail.subject.isEmpty ? "无主题" : mail.subject).font(UIType.body)
                Text("\(mail.sender) · \(displayTime(mail.date))").font(UIType.small).foregroundStyle(Palette.muted)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(CossToggleStyle()).padding(.horizontal, 12).padding(.vertical, 8)
            CossSeparator()
          }
        }.accessibilityElement(children: .contain).accessibilityLabel("可整理的邮件")
      } footer: {
        HStack {
          ActionButton(title: "上一页", icon: .chevronLeft, size: .compact) { offset = max(0, offset - 50) }
            .disabled(loading || offset == 0)
          Spacer()
          ActionButton(title: "下一页", icon: .chevronRight, size: .compact) {
            if let next = page?.nextOffset { offset = next }
          }.disabled(loading || page?.nextOffset == nil)
        }.padding(8).background(Palette.canvas)
      }
      if label == nil {
        Toggle("更新已有整理结果", isOn: $force).toggleStyle(CossToggleStyle()).font(UIType.caption)
      }
    }.padding(20).disabled(submitting)
  }

  private func review(_ preview: Trial) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(preview.matches.isEmpty ? "没有邮件符合条件" : "命中 \(preview.matches.count) 封邮件")
        .font(UIType.section).accessibilityAddTraits(.isHeader)
      if let error { WorkflowNotice(text: error, color: Palette.destructive) }
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(preview.matches) { match in
            Text(match.subject.isEmpty ? "无主题" : match.subject)
              .font(UIType.body).frame(maxWidth: .infinity, alignment: .leading)
            CossSeparator()
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
  }

  private func submit() {
    submitting = true
    error = nil
    Task {
      defer { submitting = false }
      do {
        if let preview {
          try await store.backend.perform("/mail-organization/apply", body: ["id": preview.id, "approved": true])
          try await store.refresh()
          dismiss()
        } else if let label {
          preview = try await store.backend.request("/mail-organization/trial", method: "POST",
            body: ["accountId": accountID, "messageIds": selected.sorted(), "labelId": label.id], timeout: 600)
        } else {
          let jobs: [AgentJob] = try await store.backend.request("/mail-organization/run", method: "POST",
            body: ["accountId": accountID, "messageIds": selected.sorted(), "force": force,
              "expectedLabelIds": enabledLabelIDs])
          let queued = jobs.filter { $0.status != "completed" }.count
          store.notice = queued == 0 ? "所选邮件已整理。" : "已提交 \(queued) 封邮件，可在活动记录查看。"
          dismiss()
        }
      } catch { self.error = error.localizedDescription }
    }
  }
}
