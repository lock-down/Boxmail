import AppKit
import BoxmailCore
import Observation
import SwiftUI

@Observable @MainActor final class MailStore {
  var accounts: [MailAccount] = []
  var messages: [MailMessage] = []
  var drafts: [MailDraft] = []
  var attachments: [MailAttachment] = []
  var jobs: [AgentJob] = []
  var events: [AuditEvent] = []
  var settings = SettingsData()
  var accountId = ""
  var selectedMessageId: String?
  var destination: MailDestination = .inbox
  var search = ""
  var filter = "全部"
  var busy: Set<String> = []
  var error: String?
  var notice: String?
  var pendingMutations = 0
  var credentialAuthorizationAccounts: Set<String> = []
  var ready = false
  var showSettings = false
  var settingsTab = "AI 助手"
  var composer: MailDraft?
  var previewAttachment: MailAttachment?
  var mailAITab: MailAITab?
  var mailAIErrors: [String: String] = [:]
  var activeAIMessageId: String?
  var activeAIAttachmentId: String?
  var organizeError: String?
  private var polling: Task<Void, Never>?
  private var organizePolling: Task<Void, Never>?
  var currentAccount: MailAccount? { accounts.first { $0.id == accountId } }
  var selectedMessage: MailMessage? { messages.first { $0.id == selectedMessageId } }
  var accountMessages: [MailMessage] { messages.filter { $0.accountId == accountId } }
  var unreadInboxMessages: [MailMessage] {
    accountMessages.filter { $0.folder == "inbox" && $0.unread }
  }
  var accountAttachments: [MailAttachment] {
    let ids = Set(accountMessages.flatMap(\.attachmentIds))
    return attachments.filter { ids.contains($0.id) }
  }
  var filteredMessages: [MailMessage] {
    accountMessages.filter { m in
      let inFolder: Bool
      if !search.isEmpty {
        inFolder = true
      } else {
        switch destination {
        case .starred: inFolder = m.starred && m.folder != "trash"
        case .summary: inFolder = m.summary != nil && m.folder != "trash"
        case .replies, .analysis: inFolder = m.folder == "inbox"
        default: inFolder = m.folder == destination.rawValue
        }
      }
      let searchable =
        [m.subject, m.sender, m.senderEmail, m.body, m.category]
        + m.attachmentIds.compactMap { id in
          attachments.first { $0.id == id }.map {
            $0.name + " " + $0.text + " " + ($0.analysis ?? "")
          }
        }
      return inFolder
        && (search.isEmpty || searchable.contains { $0.localizedCaseInsensitiveContains(search) })
        && (filter != "未读" || m.unread) && (filter != "有附件" || !m.attachmentIds.isEmpty)
        && (filter != "AI 已总结" || m.summary != nil)
    }
  }
  func load() async {
    do {
      try await BackendService.shared.start()
      try await refresh()
      ready = true
      selectedMessageId = filteredMessages.first?.id
      if messages.contains(where: { message in
        message.uid != nil && message.bodyVersion != 1
          && accounts.contains { $0.id == message.accountId && !$0.isDemo }
      }) {
        await syncAll(silent: true)
      }
      polling = Task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(settings.preferences.syncMinutes * 60))
          if !Task.isCancelled { await syncAll(silent: true) }
        }
      }
    } catch { self.error = error.localizedDescription }
  }
  func refresh() async throws {
    let state: AppSnapshot = try await BackendService.shared.request("/state")
    accounts = state.accounts
    messages = state.messages
    drafts = state.drafts
    attachments = state.attachments
    jobs = state.jobs
    events = state.events
    settings = state.settings
    pendingMutations = state.pendingMutations
    if !accounts.contains(where: { $0.id == accountId }) {
      accountId = accounts.first(where: { !$0.isDemo })?.id ?? accounts.first?.id ?? ""
    }
    watchOrganizer()
  }
  func action(_ name: String, _ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy.contains(name) else { return }
    busy.insert(name)
    Task {
      defer { busy.remove(name) }
      do {
        try await operation()
        try await refresh()
      } catch {
        self.error = error.localizedDescription
        try? await refresh()
      }
    }
  }
  func navigate(_ value: MailDestination) {
    mailAITab = nil
    destination = value
    filter = "全部"
    search = ""
    selectedMessageId = filteredMessages.first?.id
  }
  func select(_ message: MailMessage) {
    if selectedMessageId != message.id { mailAITab = message.summary == nil ? nil : .summary }
    selectedMessageId = message.id
    if message.unread && settings.preferences.markRead { update(message, ["unread": false]) }
  }
  func openMail(_ message: MailMessage, tab: MailAITab? = nil) {
    accountId = message.accountId
    destination = MailDestination(rawValue: message.folder) ?? .inbox
    search = ""
    filter = "全部"
    select(message)
    mailAITab = tab
  }
  func showMailAI(_ tab: MailAITab, message: MailMessage) {
    mailAITab = tab
    if activeAIMessageId != message.id { mailAIErrors[message.id] = nil }
    if tab == .summary && message.summary == nil { generate(task: "summary", message: message) }
    if tab == .translate && message.translation == nil {
      generate(task: "translate", message: message)
    }
  }
  func update(_ message: MailMessage, _ changes: [String: Any]) {
    action("message-\(message.id)") {
      try await BackendService.shared.perform(
        "/messages/\(message.id)", method: "PATCH", body: changes)
    }
  }
  func syncAll(silent: Bool = false) async {
    guard !busy.contains("sync") else { return }
    busy.insert("sync")
    defer { busy.remove("sync") }
    let real = accounts.filter { !$0.isDemo }
    if real.isEmpty {
      if !silent {
        showSettings = true
        settingsTab = "账号"
      }
      return
    }
    var failures: [String] = []
    for account in real {
      do {
        let password = try KeychainService.read("mail-\(account.id)", allowInteraction: !silent)
        credentialAuthorizationAccounts.remove(account.id)
        try await BackendService.shared.perform(
          "/sync", body: ["accountId": account.id, "password": password])
      } catch {
        if KeychainService.requiresAuthorization(error) {
          credentialAuthorizationAccounts.insert(account.id)
          if silent { continue }
        }
        failures.append("\(account.email)：\(error.localizedDescription)")
      }
    }
    do { try await refresh() } catch { failures.append(error.localizedDescription) }
    if !failures.isEmpty {
      error = failures.joined(separator: "\n")
    } else if !silent {
      notice = "邮箱同步完成"
    }
  }
  func newDraft(reply: MailMessage? = nil, forward: Bool = false, all: Bool = false) {
    var draft = MailDraft(
      accountId: accountId,
      body: settings.preferences.signature.isEmpty ? "" : "\n\n" + settings.preferences.signature)
    if let reply {
      draft.subject = (forward ? "Fwd: " : "Re: ") + reply.subject
      draft.to = forward ? "" : reply.senderEmail
      draft.inReplyTo = reply.messageId
      draft.sourceMessageId = reply.id
      if all {
        draft.cc = reply.cc.split(separator: ",").map {
          String($0).trimmingCharacters(in: .whitespaces)
        }.filter { $0 != currentAccount?.email }.joined(separator: ", ")
      }
      if forward {
        draft.body =
          "\n\n---------- 转发邮件 ----------\n发件人：\(reply.sender) <\(reply.senderEmail)>\n日期：\(reply.date)\n主题：\(reply.subject)\n\n\(reply.body)"
        draft.attachmentIds = reply.attachmentIds
      }
    }
    composer = draft
  }
  func runAI(
    task: String, message: MailMessage? = nil, attachment: MailAttachment? = nil,
    prompt: String = "", body: String = "", tone: String = "正式", length: String = "适中",
    replyPreset: ReplyPreset? = nil, preview: Bool = false
  ) async throws -> AgentJob {
    guard !busy.contains("agent") else { throw BackendService.shared.failure("AI 正在执行任务，请稍候") }
    busy.insert("agent")
    defer { busy.remove("agent") }
    let key = try KeychainService.read("ai-key")
    var input: [String: Any] = [
      "task": task, "apiKey": key, "accountId": message?.accountId ?? accountId, "prompt": prompt,
      "body": body,
      "tone": tone, "length": length,
    ]
    if let message { input["messageId"] = message.id }
    if let attachment { input["attachmentId"] = attachment.id }
    if let replyPreset { input["replyPreset"] = replyPreset.rawValue }
    if preview { input["preview"] = true }
    let job: AgentJob = try await BackendService.shared.request(
      "/agent", method: "POST", body: input, timeout: TimeInterval(settings.ai.timeout + 30))
    try await refresh()
    return job
  }
  func generate(
    task: String, message: MailMessage, attachment: MailAttachment? = nil, prompt: String = "",
    replyPreset: ReplyPreset? = nil, preview: Bool = false
  ) {
    guard !busy.contains("agent"), activeAIMessageId == nil else { return }
    if let tab = MailAITab(rawValue: task) { mailAITab = tab }
    mailAIErrors[message.id] = nil
    activeAIMessageId = message.id
    activeAIAttachmentId = attachment?.id
    Task {
      defer {
        activeAIMessageId = nil
        activeAIAttachmentId = nil
      }
      do {
        let job = try await runAI(
          task: task, message: message, attachment: attachment, prompt: prompt,
          replyPreset: replyPreset, preview: preview)
        if !preview, let id = job.result?.draftId { composer = drafts.first { $0.id == id } }
      } catch {
        mailAIErrors[message.id] = error.localizedDescription
      }
    }
  }
  func useReply(_ job: AgentJob) {
    action("use-reply") {
      let draft: MailDraft = try await BackendService.shared.request(
        "/jobs/\(job.id)/draft", method: "POST")
      self.composer = draft
    }
  }
  var latestOrganization: AgentJob? {
    jobs.first { $0.task == "classify" && $0.accountId == accountId }
  }
  func organize(scope: String = "unclassified", limit: Int = 50, retry job: AgentJob? = nil) {
    guard !busy.contains("organize-control") else { return }
    busy.insert("organize-control")
    organizeError = nil
    Task {
      defer { busy.remove("organize-control") }
      do {
        let key = try KeychainService.read("ai-key")
        let updated: AgentJob = try await BackendService.shared.request(
          job.map { "/jobs/\($0.id)/retry" } ?? "/organize", method: "POST",
          body: ["accountId": accountId, "apiKey": key, "scope": scope, "limit": limit])
        replaceJob(updated)
        watchOrganizer()
      } catch { organizeError = error.localizedDescription }
    }
  }
  func pauseOrganization(_ job: AgentJob) {
    action("organize-control") {
      let updated: AgentJob = try await BackendService.shared.request(
        "/jobs/\(job.id)/pause", method: "POST")
      self.replaceJob(updated)
    }
  }
  private func replaceJob(_ job: AgentJob) {
    jobs.removeAll { $0.id == job.id }
    jobs.append(job)
    jobs.sort { $0.createdAt > $1.createdAt }
  }
  private func watchOrganizer() {
    guard organizePolling == nil,
      jobs.contains(where: { $0.task == "classify" && $0.status == "running" })
    else { return }
    organizePolling = Task {
      defer { organizePolling = nil }
      while !Task.isCancelled {
        let running = jobs.filter { $0.task == "classify" && $0.status == "running" }
        if running.isEmpty { break }
        do {
          for job in running {
            let updated: AgentJob = try await BackendService.shared.request("/jobs/\(job.id)")
            replaceJob(updated)
          }
          organizeError = nil
          if !jobs.contains(where: { $0.task == "classify" && $0.status == "running" }) {
            try await refresh()
          }
        } catch {
          if !Task.isCancelled { organizeError = "暂时无法获取进度，正在重新连接。" }
        }
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }
  func toggleTodo(message: MailMessage, todo: MailTodo) {
    action("todo") {
      try await BackendService.shared.perform(
        "/todos", body: ["messageId": message.id, "todoId": todo.id, "done": !todo.done])
    }
  }
  func download(_ attachment: MailAttachment, preview: Bool = false) {
    action("download") {
      let file: FileResponse = try await BackendService.shared.request(
        "/attachments/\(attachment.id)")
      guard let data = Data(base64Encoded: file.content) else {
        throw BackendService.shared.failure("附件数据无效")
      }
      if preview {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "BoxmailPreview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(attachment.id + "-" + file.name)
        try data.write(to: url)
        NSWorkspace.shared.open(url)
      } else {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
      }
    }
  }
  func stop() {
    polling?.cancel()
    organizePolling?.cancel()
    KeychainService.clearSession()
    BackendService.shared.stop()
  }
}
