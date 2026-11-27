import AppKit
import BoxmailCore
import Network
import Observation
import SwiftUI

@Observable @MainActor final class MailStore {
  let composerWindow = ComposerWindow()
  let followUps: FollowUpStore
  let sendQueue: SendQueueStore
  let rules: RuleWorkspaceStore
  let notifications: NotificationCoordinator
  var attachmentPreviewIds: [String] = []
  var attachmentPreviewIndex = 0
  @ObservationIgnored let backend: BackendService
  @ObservationIgnored let readMailPassword: @MainActor (String) throws -> String
  @ObservationIgnored var conversationBodyRequests: [String: UUID] = [:]
  @ObservationIgnored var attachmentPreviewRequest: Task<Void, Never>?
  @ObservationIgnored var sourceMessageRequest: Task<Void, Never>?
  @ObservationIgnored private var refreshGeneration = UUID()
  @ObservationIgnored private var draftOpenGeneration = UUID()
  init(backend: BackendService? = nil, readMailPassword: (@MainActor (String) throws -> String)? = nil) {
    let service = backend ?? .shared
    self.backend = service
    followUps = FollowUpStore(backend: service)
    sendQueue = SendQueueStore(backend: service)
    rules = RuleWorkspaceStore(backend: service)
    notifications = NotificationCoordinator(backend: service)
    self.readMailPassword = readMailPassword ?? CredentialService.mailPassword(for:)
  }

  var accounts: [MailAccount] = []
  var messages: [MailMessage] = []
  var drafts: [MailDraft] = []
  var attachments: [MailAttachment] = []
  @ObservationIgnored var lastWorkspaceStatus: WorkspaceStatusSnapshot?
  var lastMessageRevision = 0
  var workspaceListRevision = 0
  var jobs: [AgentJob] = []
  var events: [AuditEvent] = []
  var settings = SettingsData()
  var categories = MailCategory.defaults
  var searchIndex: SearchIndexStatus?
  var searchAllAccounts = false
  var unifiedInbox = false
  var listCategory = ""
  var listLabelID: String?
  var labelReturnSource: MailSourceContext?
  var showLabelManager = false
  var dismissedOrganizationPrompts: Set<String> = []
  var organizationBatchProgress: [OrganizationBatch] = []
  var hiddenOrganizationBatchID: String?
  var organizationProgressRevision = 0
  var savedSearches: [SavedSearch] = []
  var activeSavedSearchId: String?
  var conversation: MailConversation?
  var conversationAnchor: String?
  var conversationError: String?
  var conversationBodies: [String: MailMessage] = [:]
  var restoreRevision = 0 {
    didSet {
      organizationWorkspaces = [:]
      dismissedOrganizationPrompts = []
      organizationBatchProgress = []
      hiddenOrganizationBatchID = nil
      organizationProgressRevision += 1
      translationReading = nil
      translationPreferences = [:]
      translationResults = [:]
      translationRequests = []
      translationErrors = [:]
      labelReturnSource = nil
      followUps.resetPosition()
      followUps.dismissedItem = nil
      followUps.revision += 1
      summaryListChange = nil
      mailSource = nil
      sourceMessageRequest?.cancel()
      attachmentPreviewRequest?.cancel()
    }
  }
  var accountId = ""
  var selectedMessageId: String? {
    didSet { if selectedMessageId != oldValue { translationReading = nil } }
  }
  var selectedMessageIds: Set<String> = []
  var mailListFocusRequest = 0
  var restoredMailQueryKey: String?
  var mailRevealRequest: MailRevealRequest?
  var mailSource: MailSourceContext?
  var organizationWorkspaces: [String: OrganizationWorkspaceState] = [:]
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
  var credentialIssueAccounts: Set<String> = []
  var ready = false
  var starting = false
  var startupError: String?
  var showSettings = false
  var settingsTab = "AI"
  var composer: MailDraft?
  var composerSendPlan: SendPlan?
  var previewAttachment: MailAttachment?
  var mailAITab: MailAITab?
  var attachmentLoadErrors: Set<String> = []
  var aiOutputs: [String: AIStreamOutput] = [:]
  var aiStreamTask: Task<Void, Never>?
  var translationReading: MailTranslationReading?
  var translationPreferences: [String: MailTranslationPreference] = [:]
  var translationResults: [MailTranslationKey: MailTranslationResult] = [:]
  var translationRequests: Set<MailTranslationKey> = []
  var translationErrors: [MailTranslationKey: String] = [:]
  var summaryListChange: SummaryListChange?
  var summaryListError: String?
  var pageMessages: [MailMessage] = []
  var groupMailBySender = false
  var senderGroups: [MailSenderGroup] = []
  var senderGroupTotal = 0
  var senderGroupsLoaded = false
  var expandedSenderGroups: Set<String> = []
  var senderGroupMessages: [String: [MailMessage]] = [:]
  var senderGroupNextOffsets: [String: Int] = [:]
  var senderGroupLoading: Set<String> = []
  var senderGroupErrors: [String: String] = [:]
  var senderRevealedMessage: MailMessage?
  @ObservationIgnored var senderGroupRevision = UUID()
  @ObservationIgnored var senderGroupGenerations: [String: UUID] = [:]
  var listCategoryCounts: [String: Int] = [:]
  var listUnreadCount = 0
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
  var syncStatusIssue: String?
  @ObservationIgnored var syncContentRefresh: Task<Void, Never>?
  @ObservationIgnored var syncPollInterval: Duration = .seconds(1)
  var pinnedMessageId: String?
  var pinnedQueryKey = ""
  var wakeObserver: NSObjectProtocol?
  var networkMonitor: NWPathMonitor?
  var lastNetworkSatisfied: Bool?
  var externalPreviewFiles: [AttachmentPreviewFile] = []
  private var polling: Task<Void, Never>?
  private var workspaceMonitoring: Task<Void, Never>?
  var currentAccount: MailAccount? { accounts.first { $0.id == accountId } }
  var selectedMessage: MailMessage? {
    guard let id = selectedMessageId else { return nil }
    return detailCache[id] ?? filteredMessages.first { $0.id == id } ?? messages.first { $0.id == id }
  }
  var selectedMailForCommands: MailMessage? {
    guard ready, composer == nil, !showSettings, previewAttachment == nil, isMailWorkspace,
      selectedMails.count == 1, let message = selectedMessage, message.draftId == nil,
      selectedMails.first?.id == message.id else { return nil }
    return message
  }
  var accountMessages: [MailMessage] { messages.filter { unifiedInbox && supportsUnifiedScope || $0.accountId == accountId } }
  var trashMessages: [MailMessage] { accountMessages.filter { $0.folder == "trash" } }
  var unreadInboxMessages: [MailMessage] {
    accountMessages.filter { $0.folder == "inbox" && $0.unread }
  }

  var filteredMessages: [MailMessage] {
    guard pageKey == mailQueryKey else { return [] }
    if usesSenderGroups { return visibleSenderMessages }
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
    let startedAt = Date()
    do {
      try await self.backend.start()
      backend.diagnostics.record(
        "startup.phase",
        ["phase": "service", "durationMs": String(Int(Date().timeIntervalSince(startedAt) * 1000))])
      if let message = self.backend.startupNotice { notice = message }
      try await refresh()
      ready = true
      backend.diagnostics.record(
        "startup.ready",
        [
          "durationMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
          "count": String(messages.count),
        ])
      selectedMessageId = filteredMessages.first?.id
      notifications.openPendingDestination(in: self)
      startWorkspaceMonitoring()
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
    } catch {
      backend.diagnostics.record("service.start.failed", RuntimeDiagnostics.errorFields(error))
      startupError = error.localizedDescription
    }
  }
  private func startWorkspaceMonitoring() {
    workspaceMonitoring = Task {
      await loadSavedSearches()
      while !Task.isCancelled {
        await observeWorkspaceChanges()
        await notifications.poll(store: self)
        if [.drafts, .outbox].contains(destination) { await sendQueue.load() }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
      }
    }
  }
  func refresh(reloadContent: Bool = true) async throws {
    let measuringStartup = starting && !ready
    var phaseStarted = Date()
    func measure(_ phase: String) {
      if measuringStartup {
        backend.diagnostics.record(
          "startup.phase",
          [
            "phase": phase,
            "durationMs": String(Int(Date().timeIntervalSince(phaseStarted) * 1000)),
          ])
      }
      phaseStarted = Date()
    }
    let generation = UUID()
    let revision = restoreRevision
    refreshGeneration = generation
    let state: AppSnapshot = try await self.backend.request(
      "/state?compact=1&previews=0", timeout: reloadContent ? 190 : 30)
    try Task.checkCancellation()
    guard generation == refreshGeneration, revision == restoreRevision else { return }
    measure("snapshot")
    accounts = state.accounts
    organizationWorkspaces = organizationWorkspaces.filter { key, _ in accounts.contains { $0.id == key } }
    if let source = mailSource, !accounts.contains(where: { $0.id == source.accountId }) {
      mailSource = nil
    }
    credentialIssueAccounts.formIntersection(accounts.map(\.id))
    messages = state.messages
    lastMessageRevision = state.messageRevision ?? 0
    drafts = state.drafts
    let keptAttachments = Set(
      (selectedMessage?.attachmentIds ?? []) + [previewAttachment?.id].compactMap { $0 })
    attachmentCache = attachmentCache.filter { keptAttachments.contains($0.key) }
    attachments = state.attachments.map { attachmentCache[$0.id] ?? $0 }
    workspaceListRevision &+= 1
    jobs = state.jobs
    events = state.events
    settings = state.settings
    CredentialService.useReferences(settings.credentialReferences ?? [:])
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
    measure("apply")
    await loadMessages(reset: true, preserveSelection: true)
    measure("first-page")
    guard generation == refreshGeneration, revision == restoreRevision else { return }
    if let id = selectedMessageId, !ids.contains(id) {
      selectedMessageId = filteredMessages.first?.id
    }
    if reloadContent || selectedMessageId.map({ detailCache[$0] == nil }) == true {
      await loadSelectedMessage()
    } else {
      await loadConversation()
    }
    measure("selected-content")
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
    let value = value == .summary ? MailDestination.followUps : value
    if mailSource?.destination == value { returnToMailSource(); return }
    mailSource = nil
    mailRevealRequest = nil
    restoredMailQueryKey = nil
    selectedMessageIds = []
    mailAITab = nil
    destination = value
    filter = "全部"
    listCategory = ""
    listLabelID = nil
    labelReturnSource = nil
    activeSavedSearchId = nil
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
    if composer != nil { composerWindow.bringToFront(); return }
    guard !busy.contains("draft-load") else { return }
    guard let draft = drafts.first(where: { $0.id == id }), draft.status != "sending" else {
      error = "草稿已发送、移除或正在发送，请刷新后重试。"
      return
    }
    let generation = UUID()
    let revision = restoreRevision
    draftOpenGeneration = generation
    if draft.status != "queued", sendQueue.currentPlans[id] == nil, draft.bodyLoaded != false {
      composerSendPlan = nil
      composer = draft
      return
    }
    busy.insert("draft-load")
    Task {
      defer { if draftOpenGeneration == generation { busy.remove("draft-load") } }
      do {
        if draft.status == "queued", sendQueue.currentPlans[id]?.accountId != draft.accountId {
          await sendQueue.load()
        }
        var full: MailDraft = try await self.backend.request("/drafts/\(id)")
        try Task.checkCancellation()
        guard generation == draftOpenGeneration, revision == restoreRevision, composer == nil,
          let latest = drafts.first(where: { $0.id == id }), latest.accountId == full.accountId,
          latest.status != "sending", full.status != "sending" else { return }
        let plan = sendQueue.currentPlans[id].flatMap { $0.accountId == full.accountId ? $0 : nil }
        if let plan, plan.canChange, ["draft", "queued"].contains(full.status) {
          try await sendQueue.change(plan, pause: true)
          guard generation == draftOpenGeneration, revision == restoreRevision, composer == nil else { return }
          full.status = "queued"
          composerSendPlan = plan
        } else {
          if plan?.status == "uncertain" { full.status = "uncertain" }
          guard full.status != "queued" else { throw backend.failure("发送计划已变化，请刷新草稿箱后重试。") }
          composerSendPlan = nil
        }
        composer = full
      } catch {
        if generation == draftOpenGeneration, revision == restoreRevision, composer == nil {
          self.error = "草稿正文未能加载，原草稿已保留。\(error.localizedDescription)"
        }
      }
    }
  }
  func openMail(_ message: MailMessage, tab: MailAITab? = nil) {
    if isMailWorkspace, filteredMessages.contains(where: { $0.id == message.id }) {
      select(message); mailAITab = tab
      mailRevealRequest = .init(messageId: message.id, queryKey: mailQueryKey)
      return
    }
    if [.organize, .followUps, .attachments].contains(destination) && search.isEmpty {
      mailSource = captureSourceContext()
    }
    unifiedInbox = false
    listCategory = ""
    listLabelID = nil
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
  func update(_ message: MailMessage, _ changes: [String: Any], undoable: Bool = true) {
    if undoable {
      updateMessages([message], changes: changes)
      return
    }
    action("message-\(message.id)") {
      try await self.backend.perform(
        "/messages/\(message.id)", method: "PATCH", body: changes)
    }
  }
  func restore(_ message: MailMessage) {
    restoreMessages([message])
  }
  func emptyTrash(account: MailAccount) {
    action("empty-trash-\(account.id)") {
      var input: [String: Any] = ["accountId": account.id, "approved": true]
      if !account.isDemo { input["password"] = try CredentialService.mailPassword(for: account.id) }
      try await self.backend.perform("/trash/empty", body: input)
    }
  }
  func newDraft(reply: MailMessage? = nil, forward: Bool = false, all: Bool = false) {
    if composer != nil { composerWindow.bringToFront(); return }
    guard !showSettings, previewAttachment == nil, !busy.contains("draft-load"),
      reply == nil || !busy.contains("compose-reply")
    else { return }
    let generation = UUID(), revision = restoreRevision
    draftOpenGeneration = generation
    composerSendPlan = nil
    if let reply {
      action("compose-reply") {
        let draft: MailDraft = try await self.backend.request(
          "/messages/\(reply.id)/reply-draft", method: "POST",
          body: ["all": all, "forward": forward])
        guard self.composer == nil, !self.showSettings, self.previewAttachment == nil,
          self.draftOpenGeneration == generation,
          self.restoreRevision == revision
        else { return }
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
        body: signature(for: accountId).isEmpty ? "" : "\n\n" + signature(for: accountId))
    }
  }
  func runWriting(
    task: String, accountId: String, message: MailMessage? = nil,
    prompt: String = "", body: String = "", tone: String = "正式", length: String = "适中",
    outputLanguage: String = "跟随来信", writingStyle: String = "",
    writingScope: String, writingSubject: String? = nil
  ) async throws -> AgentJob {
    let runsInBackground = task == "reply"
    guard !busy.contains("agent") else { throw self.backend.failure("AI 正在执行任务，请稍候") }
    busy.insert("agent")
    watchAIOutput()
    defer { busy.remove("agent") }
    let key = try CredentialService.read(settings.ai.credentialAccount)
    var input: [String: Any] = [
      "task": task, "apiKey": key, "providerId": settings.ai.providerId,
      "accountId": accountId, "prompt": prompt, "preview": true, "writingScope": writingScope,
      "body": body,
      "tone": tone, "length": length, "outputLanguage": outputLanguage, "writingStyle": writingStyle,
    ]
    if let message { input["messageId"] = message.id }
    if let writingSubject { input["subject"] = writingSubject }
    if runsInBackground { input["background"] = true }
    var job: AgentJob = try await self.backend.request(
      "/agent", method: "POST", body: input,
      timeout: runsInBackground ? 15 : TimeInterval(settings.ai.timeout + 30))
    if runsInBackground {
      replaceJob(job)
      var pollingFailures = 0
      while job.status == "running" {
        try await Task.sleep(for: .seconds(1))
        do {
          job = try await self.backend.request("/jobs/\(job.id)", timeout: 30)
          replaceJob(job)
          pollingFailures = 0
        } catch is CancellationError { throw CancellationError()
        } catch {
          pollingFailures += 1
          if pollingFailures >= 5 { throw error }
        }
      }
      if job.status != "completed" {
        throw self.backend.failure(job.error ?? "AI 任务未完成，可重试这封邮件。")
      }
    }
    return job
  }
  func useReply(_ job: AgentJob) {
    guard composer == nil, !showSettings, previewAttachment == nil else { return }
    let revision = restoreRevision
    action("use-reply") {
      let draft: MailDraft = try await self.backend.request(
        "/jobs/\(job.id)/draft", method: "POST")
      guard self.composer == nil, !self.showSettings, self.previewAttachment == nil,
        revision == self.restoreRevision else { return }
      self.composer = draft
    }
  }
  func replaceJob(_ job: AgentJob) {
    jobs.removeAll { $0.id == job.id }
    jobs.append(job)
    jobs.sort { $0.createdAt > $1.createdAt }
  }
  func download(_ attachment: MailAttachment, preview: Bool = false) {
    action("download") {
      let file: FileResponse = try await self.backend.request(
        "/attachments/\(attachment.id)")
      guard let data = Data(base64Encoded: file.content) else {
        throw self.backend.failure("附件数据无效")
      }
      if preview {
        let original = try AttachmentPreviewFile(name: file.name, data: data)
        guard NSWorkspace.shared.open(original.url) else {
          original.remove()
          throw self.backend.failure("没有可打开此格式的应用，请下载后选择合适的应用。")
        }
        self.externalPreviewFiles.append(original)
      } else {
        if let url = FilePanel.save(title: "保存附件", name: file.name) {
          try data.write(to: url)
        }
      }
    }
  }
  func stop() async {
    workspaceMonitoring?.cancel()
    syncContentRefresh?.cancel()
    aiStreamTask?.cancel()
    attachmentPreviewRequest?.cancel()
    sourceMessageRequest?.cancel()
    polling?.cancel()
    networkMonitor?.cancel()
    externalPreviewFiles.forEach { $0.remove() }
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    await self.backend.stop()
  }
}
