import BoxmailCore
import SwiftUI

struct OrganizationMailPicker: View {
  private static let pageSize = 50

  @Bindable var store: MailStore
  let label: MailCategory?
  @Environment(\.dismiss) private var dismiss
  @ViewState private var accountID = ""
  @ViewState private var search = ""
  @ViewState private var range = "all"
  @ViewState private var offset = 0
  @ViewState private var page: CandidatePage?
  @ViewState private var selected: [Candidate] = []
  @ViewState private var showsSelected = false
  @ViewState private var recentCount = 50
  @ViewState private var review: SubmissionPreview?
  @ViewState private var batch: OrganizationBatch?
  @ViewState private var force = false
  @ViewState private var loading = false
  @ViewState private var working = false
  @ViewState private var loadError: String?
  @ViewState private var error: String?

  private struct CandidatePage: Decodable {
    let messages: [Candidate]
    let total, outside, limit: Int
    let nextOffset: Int?
  }

  private struct Candidate: Decodable, Identifiable {
    let id, subject, sender, date, folder: String
  }

  private struct CandidateRequest: Equatable {
    let accountID, search, range: String
    let offset: Int
    let selected: [String]
    var body: [String: Any] {
      ["accountId": accountID, "query": search, "unread": range == "unread", "offset": offset, "selected": selected]
    }
  }

  private struct SubmissionPreview: Decodable {
    let receipt, batchId: String
    let usesLabelConditions: Bool
    let items: [Item]
    var ready: Bool { items.contains { $0.status == "new" || $0.status == "update" } }

    struct Item: Decodable, Identifiable {
      let id, status: String
      let subject, reason: String?
    }
  }

  private var title: String { label == nil ? "整理邮件" : "试用标签条件" }
  private var candidateRequest: CandidateRequest {
    .init(accountID: accountID, search: search, range: range, offset: offset, selected: selected.map(\.id))
  }
  private var submission: [String: Any] {
    var input: [String: Any] = ["accountId": accountID, "messageIds": selected.map(\.id), "force": force,
      "expectedFolders": Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.folder) })]
    if let label { input["labelId"] = label.id }
    return input
  }

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: title, subtitle: label?.name ?? "", closeLabel: "关闭") { dismiss() }
        .padding(20).disabled(working)
      CossSeparator()
      if let batch {
        OrganizationBatchView(store: store, initial: batch)
      } else if let review {
        confirmation(review)
      } else {
        selection
      }
      if batch != nil {
        HStack(spacing: 12) {
          Text("关闭后可在待办清单查看进度。").font(UIType.caption).foregroundStyle(Palette.muted)
          Spacer()
          ActionButton(title: "关闭窗口", size: .form) { dismiss() }
        }.padding(.horizontal, 24).frame(height: 53).background(Palette.canvas)
      } else {
        SettingsActionBar(primaryTitle: review == nil ? "预览范围" : label == nil ? "提交整理" : "开始试用",
          isWorking: working, primaryDisabled: accountID.isEmpty || selected.isEmpty || review?.ready == false,
          cancel: { dismiss() }, primary: submit) {
          if review != nil {
            ActionButton(title: "返回选信", icon: .chevronLeft, size: .form) {
              review = nil
              error = nil
            }.disabled(working)
          } else {
            ActionButton(title: showsSelected ? "返回结果" : "查看已选",
              icon: showsSelected ? .chevronLeft : .listCheck, size: .form,
              help: showsSelected ? "返回搜索结果" : "查看已选的 \(selected.count) 封邮件") {
              showsSelected.toggle()
            }.disabled(working)
          }
        }
      }
    }
    .background(Palette.paper)
    .workspaceWindowSize(.categories)
    .interactiveDismissDisabled(working)
    .onAppear { if !store.unifiedInbox { accountID = store.accountId } }
    .onChange(of: accountID) { _, _ in
      selected = []; showsSelected = false
      clearPage()
    }
    .onChange(of: search) { _, _ in clearPage() }
    .onChange(of: range) { _, _ in clearPage() }
    .task(id: candidateRequest) {
      let request = candidateRequest
      guard !request.accountID.isEmpty else { loading = false; return }
      loading = true
      defer { if !Task.isCancelled { loading = false } }
      do {
        try await Task.sleep(for: .milliseconds(180))
        let response: CandidatePage = try await store.backend.request("/mail-organization/candidates",
          method: "POST", body: request.body)
        if !Task.isCancelled { page = response; loadError = nil }
      } catch { if !Task.isCancelled { loadError = error.localizedDescription } }
    }
  }

  private var selection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !showsSelected { candidateFilters }
      if let issue = error ?? loadError { WorkflowNotice(text: issue, color: Palette.destructive) }
      if !showsSelected, let page {
        HStack {
          Text("符合条件 \(page.total) 封 · 单次最多 \(page.limit) 封")
          Spacer(minLength: 8)
          if !loading && page.outside > 0 { Text("\(page.outside) 封已选邮件在当前结果之外") }
        }.font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted)
        bulkControls(page)
      }
      mailList
      if label == nil {
        Toggle("重新整理", isOn: $force).toggleStyle(CossToggleStyle()).font(UIType.caption)
      }
    }.padding(20).disabled(working)
  }

  private var candidateFilters: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        WorkflowSelection(title: "来源账户", selection: $accountID,
          options: [("", "选择邮箱")] + store.accounts.map { ($0.id, $0.email) }).frame(width: 224)
        WorkflowSelection(title: "邮件范围", selection: $range,
          options: [("all", "全部"), ("unread", "未读")]).frame(width: 84)
        WorkflowTextInput(label: "搜索已缓存的邮件", placeholder: "搜索邮件", text: $search)
      }
      Text("范围包括收件箱、已发送、已归档和垃圾邮件中已缓存正文的邮件。")
        .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func bulkControls(_ page: CandidatePage) -> some View {
    HStack(spacing: 8) {
      ActionButton(title: "选本页", size: .compact, help: "选择本页邮件") { add(page.messages) }
      ActionButton(title: "选全部", size: .compact, help: "选择全部搜索结果") { selectRecent(page.total) }
        .disabled(page.total + page.outside > page.limit)
      Spacer()
      CossNumberField(title: "最近邮件封数", value: $recentCount, range: 1...page.limit, size: .compact).frame(width: 86)
      ActionButton(title: "选最近", size: .compact, help: "选择指定封数的最近邮件") { selectRecent(recentCount) }
    }.disabled(loading || page.total == 0)
  }

  private var mailList: some View {
    let selectedIDs = Set(selected.map(\.id))
    let mails = showsSelected ? selected : page?.messages ?? []
    return WorkspaceListSurface {
      if showsSelected {
        HStack {
          Text("已选 \(selected.count) 封").font(UIType.section)
          Spacer()
          ActionButton(title: "清空选择", size: .compact) { selected = []; error = nil }.disabled(selected.isEmpty)
        }.padding(.horizontal, 12).padding(.vertical, 8)
        CossSeparator()
      }
    } content: {
      if !showsSelected && loading && page == nil {
        CossSpinner().padding(16).accessibilityLabel("正在搜索")
      } else if mails.isEmpty {
        Text(showsSelected ? "还没有选择邮件" : (accountID.isEmpty ? "请选择邮箱" : "没有符合条件的邮件"))
          .font(UIType.caption).foregroundStyle(Palette.muted).padding(16)
      }
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(mails) { mail in
          Toggle(isOn: Binding(get: { selectedIDs.contains(mail.id) }, set: { checked in
            if checked { add([mail]) } else { selected.removeAll { $0.id == mail.id }; error = nil }
          })) {
            VStack(alignment: .leading, spacing: 4) {
              Text(mail.subject.isEmpty ? "无主题" : mail.subject).font(UIType.body)
              Text("\(mail.sender) · \(displayTime(mail.date))").font(UIType.small).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.toggleStyle(CossToggleStyle()).padding(.horizontal, 12).padding(.vertical, 8)
          CossSeparator()
        }
      }.accessibilityElement(children: .contain).accessibilityLabel(showsSelected ? "已选择的邮件" : "可整理的邮件")
    } footer: {
      if !showsSelected {
        HStack(spacing: 8) {
          if let page { Text("本页 \(page.messages.count) 封") }
          Spacer(minLength: 8)
          PageNavigation(title: "第 \(offset / Self.pageSize + 1) 页", subject: "候选邮件",
            hasPrevious: !loading && offset > 0, hasNext: !loading && page?.nextOffset != nil, buttonSize: 24,
            previous: { turnPage(to: max(0, offset - Self.pageSize)) }, next: {
              if let next = page?.nextOffset { turnPage(to: next) }
            })
        }.font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
          .padding(.horizontal, 12).frame(height: 32).background(Palette.canvas)
          .overlay(alignment: .top) { CossSeparator() }
      }
    }.id(showsSelected ? "selected" : "\(accountID)-\(range)-\(search)-\(offset)")
  }

  private func clearPage() {
    turnPage(to: 0)
    error = nil
    loadError = nil
  }

  private func turnPage(to offset: Int) {
    self.offset = offset
    page = nil
    loading = !accountID.isEmpty
  }

  private func add(_ mails: [Candidate]) {
    let ids = Set(selected.map(\.id))
    let additions = mails.filter { !ids.contains($0.id) }
    guard let limit = page?.limit, selected.count + additions.count <= limit else {
      if let limit = page?.limit { error = "单次最多选择 \(limit) 封邮件，请先移除部分已选邮件。" }
      return
    }
    selected += additions
    error = nil
  }

  private func selectRecent(_ count: Int) {
    let request = candidateRequest
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        var body = request.body
        body["offset"] = 0
        body["count"] = count
        let response: CandidatePage = try await store.backend.request("/mail-organization/candidates",
          method: "POST", body: body)
        if request == candidateRequest { add(response.messages) }
      } catch { self.error = error.localizedDescription }
    }
  }

  private func confirmation(_ preview: SubmissionPreview) -> some View {
    let counts = Dictionary(grouping: preview.items, by: \.status).mapValues(\.count)
    let fields = label != nil ? "发件人、主题、正文和匹配条件" : preview.usesLabelConditions
      ? "发件人、主题、正文、匹配条件和现有分类说明" : "主题、正文和现有分类说明"
    let subjects = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.subject) })
    let account = store.accounts.first { $0.id == accountID }?.email ?? ""
    return VStack(alignment: .leading, spacing: 12) {
      Text("确认提交范围").font(UIType.section).accessibilityAddTraits(.isHeader)
      Text("\(account) · \(preview.items.count) 封已选")
        .font(UIType.caption).foregroundStyle(Palette.muted)
      Text("新增 \(counts["new", default: 0]) · 跳过 \(counts["skipped", default: 0]) · 更新 \(counts["update", default: 0]) · 失效 \(counts["invalid", default: 0])")
        .font(UIType.body).monospacedDigit()
      Text("仅提交新增和更新的邮件。AI 服务商将收到\(fields)，附件保留在本机。")
        .font(UIType.small).foregroundStyle(Palette.muted)
      if let error { WorkflowNotice(text: error, color: Palette.destructive) }
      WorkspaceList(items: preview.items, header: { EmptyView() }, footer: { EmptyView() }) { item in
        let subject = item.subject ?? subjects[item.id] ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(subject.isEmpty ? "无主题" : subject).font(UIType.body)
              .fixedSize(horizontal: false, vertical: true)
            if let reason = item.reason {
              Text(reason).font(UIType.small).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Text(previewStatus(item.status)).font(UIType.small)
            .foregroundStyle(item.status == "invalid" ? Palette.destructive : Palette.muted)
            .frame(width: 40, alignment: .trailing)
        }.padding(.horizontal, 12).padding(.vertical, 8).accessibilityElement(children: .combine)
      }
    }.padding(20).disabled(working)
  }

  private func previewStatus(_ status: String) -> String {
    switch status {
    case "new": return "新增"
    case "update": return "更新"
    case "skipped": return "跳过"
    case "invalid": return "失效"
    default: return WorkspaceStatus.title(status)
    }
  }

  private func submit() {
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        if let review {
          var confirmed = submission
          confirmed["receipt"] = review.receipt
          confirmed["batchId"] = review.batchId
          let submitted: OrganizationBatch = try await store.backend.request(label == nil ? "/mail-organization/run" : "/mail-organization/trial",
            method: "POST", body: confirmed)
          store.recordOrganizationBatch(submitted)
          batch = submitted
        } else {
          review = try await store.backend.request("/mail-organization/preview", method: "POST", body: submission)
        }
      } catch { self.error = error.localizedDescription }
    }
  }
}
