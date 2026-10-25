import AppKit
import BoxmailCore
import Network
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
  var categories = MailCategory.defaults
  var searchIndex: SearchIndexStatus?
  var searchAllAccounts = false
  var conversation: MailConversation?
  var conversationAnchor: String?
  var conversationError: String?
  var conversationBodies: [String: MailMessage] = [:]
  var restoreRevision = 0
  var accountId = ""
  var selectedMessageId: String?
  var selectedMessageIds: Set<String> = []
  var mailRevealRequest: MailRevealRequest?
  var selectionQueryKey = ""
  var mailChange: MailChange?
  var mailActionError: String?
  @ObservationIgnored weak var mailUndoManager: UndoManager?
  var destination: MailDestination = .inbox
  var search = ""
  var searchFocusRequest = 0
  var filter = "全部"
  var busy: Set<String> = []
  var error: String?
  var notice: String?
  var pendingMutations = 0
  var credentialAuthorizationAccounts: Set<String> = []
  var ready = false
  var starting = false
  var startupError: String?
  var showSettings = false
  var settingsTab = "AI 助手"
  var composer: MailDraft?
  var previewAttachment: MailAttachment?
  var mailAITab: MailAITab?
  var mailAIErrors: [String: String] = [:]
  var activeAIMessageId: String?
  var activeAIAttachmentId: String?
  var aiOutputs: [String: AIStreamOutput] = [:]
  var aiStreamTask: Task<Void, Never>?
  var translatedMessageIds: Set<String> = []
  var summaryReplyRequest: SummaryReplyRequest?
  var summaryListChange: SummaryListChange?
  var summaryListError: String?
  var unreadSummaryProgress: String?
  var attachmentResultsMessageId: String?
  var organizeError: String?
  var attachmentBatchErrors: [String: String] = [:]
  var attachmentBatchPolling: Task<Void, Never>?
  var pageMessages: [MailMessage] = []
  var pageTotal = 0
  var nextOffset: Int?
  var pageKey = ""
  var pageGeneration = UUID()
  var listLoading = false
  var listError: String?
  var detailError: String?
  var detailCache: [String: MailMessage] = [:]
  var attachmentCache: [String: MailAttachment] = [:]
  var detailGeneration = UUID()
  var syncSnapshot: MailSyncSnapshot?
  var syncingAccountIds: Set<String> = []
  var syncingFolder: String?
  var syncCancellationRequested = false
  var syncCancelInFlight = false
  var pinnedMessageId: String?
  var pinnedQueryKey = ""
  var wakeObserver: NSObjectProtocol?
  var networkMonitor: NWPathMonitor?
  var lastNetworkSatisfied: Bool?
  var externalPreviewFiles: [AttachmentPreviewFile] = []
  private var polling: Task<Void, Never>?
  private var organizePolling: Task<Void, Never>?
  var currentAccount: MailAccount? { accounts.first { $0.id == accountId } }
  var selectedMessage: MailMessage? {
    guard let id = selectedMessageId else { return nil }
    return detailCache[id] ?? messages.first { $0.id == id } ?? pageMessages.first { $0.id == id }
  }
  var selectedMailForCommands: MailMessage? {
    guard ready, composer == nil, !showSettings, previewAttachment == nil, isMailWorkspace,
      selectedMails.count == 1, let message = selectedMessage, message.draftId == nil,
      selectedMails.first?.id == message.id else { return nil }
    return message
  }
  var accountMessages: [MailMessage] { messages.filter { $0.accountId == accountId } }
  var trashMessages: [MailMessage] { accountMessages.filter { $0.folder == "trash" } }
  var unreadInboxMessages: [MailMessage] {
    accountMessages.filter { $0.folder == "inbox" && $0.unread }
  }
  var accountAttachments: [MailAttachment] {
    let ids = Set(accountMessages.flatMap(\.attachmentIds))
    return attachments.filter { ids.contains($0.id) }
  }
  var filteredMessages: [MailMessage] {
    guard pageKey == mailQueryKey else { return [] }
    if pinnedQueryKey == mailQueryKey, let id = pinnedMessageId,
      !pageMessages.contains(where: { $0.id == id }),
      let message = detailCache[id] ?? messages.first(where: { $0.id == id })
    {
      return [message] + pageMessages
    }
    return pageMessages
  }
  func load() async {
    guard !ready, !starting else { return }
    starting = true
    startupError = nil
    defer { starting = false }
    do {
      try await BackendService.shared.start()
      if let message = BackendService.shared.startupNotice { notice = message }
      try await refresh()
      ready = true
      watchAIOutput()
      selectedMessageId = filteredMessages.first?.id
      if messages.contains(where: { message in
        message.uid != nil && message.bodyVersion != 1
          && accounts.contains { $0.id == message.accountId && !$0.isDemo }
      }) {
        await syncAll(silent: true)
      }
      startSyncMonitoring()
      polling = Task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(settings.preferences.syncMinutes * 60))
          if !Task.isCancelled { await syncAll(silent: true) }
        }
      }
    } catch { startupError = error.localizedDescription }
  }
  func refresh(reloadContent: Bool = true) async throws {
    let state: AppSnapshot = try await BackendService.shared.request(
      "/state?compact=1&previews=0", timeout: reloadContent ? 190 : 30)
    accounts = state.accounts
    messages = state.messages
    drafts = state.drafts
    let keptAttachments = Set(
      (selectedMessage?.attachmentIds ?? []) + [previewAttachment?.id].compactMap { $0 })
    attachmentCache = attachmentCache.filter { keptAttachments.contains($0.key) }
    attachments = state.attachments.map { attachmentCache[$0.id] ?? $0 }
    jobs = state.jobs
    events = state.events
    settings = state.settings
    KeychainService.useReferences(settings.credentialReferences ?? [:])
    categories = state.categories ?? MailCategory.defaults
    searchIndex = state.searchIndex
    conversationBodies = [:]
    pendingMutations = state.pendingMutations
    syncSnapshot = state.sync
    let ids = Set(messages.map(\.id) + drafts.map { "draft:" + $0.id })
    detailCache = detailCache.filter { ids.contains($0.key) }
    if !accounts.contains(where: { $0.id == accountId }) {
      accountId = accounts.first(where: { !$0.isDemo })?.id ?? accounts.first?.id ?? ""
    }
    await loadMessages(reset: true, preserveSelection: true)
    if let id = selectedMessageId, !ids.contains(id) {
      selectedMessageId = filteredMessages.first?.id
    }
    if reloadContent || selectedMessageId.map({ detailCache[$0] == nil }) == true {
      await loadSelectedMessage()
    }
    watchOrganizer()
    watchAttachmentBatches()
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
    mailRevealRequest = nil
    selectedMessageIds = []
    mailAITab = nil
    destination = value
    filter = "全部"
    search = ""
    selectedMessageId = filteredMessages.first?.id
  }
  func select(_ message: MailMessage) {
    if mailRevealRequest?.messageId != message.id { mailRevealRequest = nil }
    if selectedMessageId != message.id { mailAITab = nil }
    selectedMessageId = message.id
    selectedMessageIds = [message.id]
    selectionQueryKey = mailQueryKey
    detailError = nil
    if message.unread && settings.preferences.markRead {
      update(message, ["unread": false], undoable: false)
    }
  }
  func editDraft(_ id: String) {
    guard let draft = drafts.first(where: { $0.id == id }), draft.status != "sending" else {
      error = "草稿已发送、移除或正在发送，请刷新后重试。"
      return
    }
    composer = draft
  }
  func openMail(_ message: MailMessage, tab: MailAITab? = nil) {
    accountId = message.accountId
    destination = MailDestination(rawValue: message.folder) ?? .inbox
    search = ""
    filter = "全部"
    pinnedMessageId = message.id
    pinnedQueryKey = mailQueryKey
    select(message)
    mailAITab = tab
    mailRevealRequest = MailRevealRequest(messageId: message.id, queryKey: mailQueryKey)
  }
  func showMailAI(_ tab: MailAITab, message: MailMessage) {
    if tab == .translate { toggleTranslation(message); return }
    mailAITab = tab
    if activeAIMessageId != message.id { mailAIErrors[message.id] = nil }
    if tab == .summary && message.summary == nil { generate(task: "summary", message: message) }
  }
  func update(_ message: MailMessage, _ changes: [String: Any], undoable: Bool = true) {
    if undoable {
      updateMessages([message], changes: changes)
      return
    }
    action("message-\(message.id)") {
      try await BackendService.shared.perform(
        "/messages/\(message.id)", method: "PATCH", body: changes)
    }
  }
  func restore(_ message: MailMessage) {
    restoreMessages([message])
  }
  func unarchive(_ message: MailMessage) {
    restoreMessages([message])
  }
  func emptyTrash(account: MailAccount) {
    action("empty-trash-\(account.id)") {
      var input: [String: Any] = ["accountId": account.id, "approved": true]
      if !account.isDemo { input["password"] = try KeychainService.read("mail-\(account.id)") }
      try await BackendService.shared.perform("/trash/empty", body: input)
    }
  }
  func syncAll(silent: Bool = false, folder: String? = nil) async {
    guard !busy.contains("sync") else { return }
    busy.insert("sync")
    syncingAccountIds = []
    syncingFolder = folder
    syncCancellationRequested = false
    defer {
      busy.remove("sync")
      syncingAccountIds = []
      syncingFolder = nil
      syncCancellationRequested = false
    }
    let real = accounts.filter { !$0.isDemo && (folder == nil || $0.id == accountId) }
    if real.isEmpty {
      if !silent {
        showSettings = true
        settingsTab = "账号"
      }
      return
    }
    var failures: [String] = []
    var started = Set<String>()
    for account in real {
      if syncCancellationRequested || Task.isCancelled { break }
      do {
        let password = try KeychainService.read("mail-\(account.id)", allowInteraction: !silent)
        credentialAuthorizationAccounts.remove(account.id)
        var input: [String: Any] = [
          "accountId": account.id, "password": password, "background": true,
        ]
        if let folder { input["folder"] = folder }
        try await BackendService.shared.perform("/sync", body: input)
        started.insert(account.id)
        syncingAccountIds = started
        if syncCancellationRequested { await cancelSync() }
      } catch {
        if KeychainService.requiresAuthorization(error) {
          credentialAuthorizationAccounts.insert(account.id)
          if silent { continue }
        }
        // A lost start response or a previous polling interruption can leave a
        // healthy background sync running. Rejoin it instead of reporting a conflict.
        if let snapshot: MailSyncSnapshot = try? await BackendService.shared.request(
          "/sync-status", timeout: 30), snapshot.runningAccounts.contains(account.id)
        {
          started.insert(account.id)
          syncingAccountIds = started
          syncSnapshot = snapshot
          if syncCancellationRequested { await cancelSync() }
          continue
        }
        failures.append("\(account.email)：\(error.localizedDescription)")
      }
    }
    do {
      var pollingFailures = 0
      var lastRefresh = Date.distantPast
      var lastDownloaded = syncSnapshot?.folders.reduce(0) { $0 + ($1.downloaded ?? 0) } ?? -1
      while !started.isEmpty && !Task.isCancelled {
        let snapshot: MailSyncSnapshot
        do {
          snapshot = try await BackendService.shared.request("/sync-status", timeout: 30)
          pollingFailures = 0
        } catch is CancellationError { return
        } catch {
          pollingFailures += 1
          if pollingFailures >= 5 { throw error }
          try await Task.sleep(for: .seconds(2))
          continue
        }
        syncSnapshot = snapshot
        if !snapshot.runningAccounts.contains(where: { started.contains($0) }) {
          for result in snapshot.results
          where started.contains(result.accountId) && result.status == "failed" {
            let name = accounts.first { $0.id == result.accountId }?.email ?? "邮箱"
            failures.append("\(name)：\(result.error ?? "同步未完成")")
          }
          break
        }
        let downloaded = snapshot.folders.reduce(0) { $0 + ($1.downloaded ?? 0) }
        if downloaded != lastDownloaded && Date().timeIntervalSince(lastRefresh) >= 4 {
          try? await refresh(reloadContent: false)
          lastRefresh = Date()
          lastDownloaded = downloaded
        }
        try await Task.sleep(for: .seconds(1))
      }
      try await refresh()
    } catch is CancellationError {
      return
    } catch { failures.append(error.localizedDescription) }
    if !failures.isEmpty {
      if !silent { error = failures.joined(separator: "\n") }
    }
  }
  func newDraft(reply: MailMessage? = nil, forward: Bool = false, all: Bool = false) {
    if let reply {
      action("compose-reply") {
        let draft: MailDraft = try await BackendService.shared.request(
          "/messages/\(reply.id)/reply-draft", method: "POST",
          body: ["all": all, "forward": forward])
        self.composer = draft
      }
    } else {
      guard accounts.contains(where: { $0.id == accountId }) else {
        settingsTab = "账号"
        showSettings = true
        return
      }
      composer = MailDraft(
        accountId: accountId,
        body: settings.preferences.signature.isEmpty ? "" : "\n\n" + settings.preferences.signature)
    }
  }
  func runAI(
    task: String, message: MailMessage? = nil, attachment: MailAttachment? = nil,
    prompt: String = "", body: String = "", tone: String = "正式", length: String = "适中",
    replyPreset: ReplyPreset? = nil, preview: Bool = false, background: Bool = false
  ) async throws -> AgentJob {
    guard !busy.contains("agent") else { throw BackendService.shared.failure("AI 正在执行任务，请稍候") }
    busy.insert("agent")
    watchAIOutput()
    defer { busy.remove("agent") }
    let key = try KeychainService.read(settings.ai.credentialAccount)
    var input: [String: Any] = [
      "task": task, "apiKey": key, "providerId": settings.ai.providerId,
      "accountId": message?.accountId ?? accountId, "prompt": prompt,
      "body": body,
      "tone": tone, "length": length,
    ]
    if let message { input["messageId"] = message.id }
    if let attachment { input["attachmentId"] = attachment.id }
    if let replyPreset { input["replyPreset"] = replyPreset.rawValue }
    if preview { input["preview"] = true }
    if background { input["background"] = true }
    let preparationAllowance = attachment?.isPresentation == true ? 150 : 30
    var job: AgentJob = try await BackendService.shared.request(
      "/agent", method: "POST", body: input,
      timeout: background ? 15 : TimeInterval(settings.ai.timeout + preparationAllowance))
    if background {
      replaceJob(job)
      var pollingFailures = 0
      while job.status == "running" {
        try await Task.sleep(for: .seconds(1))
        do {
          job = try await BackendService.shared.request("/jobs/\(job.id)", timeout: 30)
          replaceJob(job)
          pollingFailures = 0
        } catch is CancellationError { throw CancellationError()
        } catch {
          pollingFailures += 1
          if pollingFailures >= 5 { throw error }
        }
      }
      if job.status != "completed" {
        throw BackendService.shared.failure(job.error ?? "AI 任务未完成，可重试这封邮件。")
      }
    }
    if background { try? await refresh(reloadContent: false) }
    else { try await refresh() }
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
        let key = try KeychainService.read(settings.ai.credentialAccount)
        let updated: AgentJob = try await BackendService.shared.request(
          job.map { "/jobs/\($0.id)/retry" } ?? "/organize", method: "POST",
          body: ["accountId": accountId, "apiKey": key, "providerId": settings.ai.providerId, "scope": scope, "limit": limit])
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
  func replaceJob(_ job: AgentJob) {
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
        let original = try AttachmentPreviewFile(name: file.name, data: data)
        guard NSWorkspace.shared.open(original.url) else {
          original.remove()
          throw BackendService.shared.failure("没有可打开此格式的应用，请下载后选择合适的应用。")
        }
        self.externalPreviewFiles.append(original)
      } else {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
      }
    }
  }
  func stop() async {
    aiStreamTask?.cancel()
    polling?.cancel()
    organizePolling?.cancel()
    attachmentBatchPolling?.cancel()
    networkMonitor?.cancel()
    externalPreviewFiles.forEach { $0.remove() }
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    KeychainService.clearSession()
    await BackendService.shared.stop()
  }
}
