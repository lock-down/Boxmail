import BoxmailCore
import Foundation

struct WorkspaceStatusSnapshot: Decodable, Equatable {
  let messageRevision: Int
  let snoozes, sendPlans: [String]
}

extension MailStore {
  func observeWorkspaceChanges() async {
    do {
      let status: WorkspaceStatusSnapshot = try await backend.request("/workspace-status", timeout: 8)
      let changed = status.messageRevision != lastMessageRevision || (lastWorkspaceStatus.map { $0.snoozes != status.snoozes || $0.sendPlans != status.sendPlans } ?? false)
      lastWorkspaceStatus = status
      if changed && !busy.contains("sync") { try await refresh(reloadContent: false) }
      if settings.preferences.realtimeSync == true && !busy.contains("sync") {
        syncSnapshot = try await backend.request("/sync-status", timeout: 8)
      }
    } catch { backend.diagnostics.record("workspace.refresh.failed", RuntimeDiagnostics.errorFields(error)) }
  }

  func attachmentWorkspace() -> AttachmentPageStore {
    if let workspace = attachmentWorkspaces[accountId] { return workspace }
    let workspace = AttachmentPageStore(backend: backend, accountId: accountId)
    attachmentWorkspaces[accountId] = workspace
    return workspace
  }
  func showAttachments(from message: MailMessage) {
    accountId = message.accountId
    let workspace = attachmentWorkspace()
    workspace.sourceMessageId = message.id; workspace.query = ""; workspace.type = "全部"
    navigate(.attachments)
  }
  func previewFile(_ attachment: MailAttachment) {
    let revision = restoreRevision
    Task {
      do {
        let message: MailMessage = try await backend.request("/messages/\(attachment.messageId)")
        guard revision == restoreRevision else { return }
        attachmentPreviewIds = message.attachmentIds
        attachmentPreviewIndex = attachmentPreviewIds.firstIndex(of: attachment.id) ?? 0
        previewAttachment = attachment
      } catch { self.error = error.localizedDescription }
    }
  }
  func previewSourceAttachment(_ id: String) {
    let revision = restoreRevision
    Task {
      do {
        let file: MailAttachment = try await backend.request("/attachments/\(id)/metadata")
        guard revision == restoreRevision else { return }
        cacheAttachment(file)
        previewFile(file)
      } catch { if revision == restoreRevision { self.error = error.localizedDescription } }
    }
  }
  func openSourceMessage(_ id: String) {
    let source = captureSourceContext()
    Task {
      do {
        let message: MailMessage = try await backend.request("/messages/\(id)")
        guard source.destination == destination, source.accountId == accountId else { return }
        if let draftId = message.draftId {
          editDraft(draftId)
          return
        }
        openMail(message); mailSource = source
      } catch { self.error = error.localizedDescription }
    }
  }
  func collectFollowUp(message: MailMessage, title: String? = nil, todo: MailTodo? = nil, sourceKey: String? = nil, snooze: Bool = false) {
    Task {
      var input: [String: Any] = ["messageId": message.id, "title": title ?? todo?.title ?? (message.subject.isEmpty ? "跟进无主题邮件" : message.subject),
        "sourceKey": sourceKey ?? todo.map { "todo:\($0.title)\u{1f}\($0.due)" } ?? "mail:\(message.id)"]
      if let todo { input["todoId"] = todo.id }
      if let item = await followUps.save(input) {
        followUps.editorRequest = item.id; followUps.suggestSnooze = snooze
        followUps.filter = item.isSnoozed ? "已延后" : item.state == "waiting" ? "等待对方" : item.state == "completed" ? "已完成" : "待我处理"
        navigate(.followUps)
      } else { error = followUps.error }
    }
  }
  var suggestedAssistantScope: AssistantScope {
    assistantScope(for: Self.assistantFolders.contains(destination) ? destination : .inbox)
  }
  static let assistantFolders: [MailDestination] = [.inbox, .drafts, .sent, .archive, .starred, .spam, .trash]

  func assistantScope(for folder: MailDestination) -> AssistantScope {
    let scopeAccount = unifiedInbox && folder != .drafts || accountId.isEmpty ? nil : accountId
    return .init(kind: "folder", query: .init(accountId: scopeAccount, folder: folder.rawValue))
  }
  func signature(for accountId: String) -> String { settings.preferences.accountSignatures?[accountId] ?? settings.preferences.signature }
}
