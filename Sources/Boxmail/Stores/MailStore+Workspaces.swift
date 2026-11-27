import BoxmailCore
import Foundation

struct WorkspaceStatusSnapshot: Decodable, Equatable {
  let messageRevision: Int
  let snoozes, sendPlans: [String]
  let followUpRevision, dueFollowUpCount: Int?
  let organizationBatches: [OrganizationBatch]?
}

extension MailStore {
  func observeWorkspaceChanges() async {
    do {
      let organizationRevision = organizationProgressRevision
      let status: WorkspaceStatusSnapshot = try await backend.request("/workspace-status", timeout: 8)
      if organizationRevision == organizationProgressRevision, let batches = status.organizationBatches,
        organizationBatchProgress != batches {
        organizationBatchProgress = batches
      }
      if lastWorkspaceStatus.map({ previous in
        previous.messageRevision != status.messageRevision || previous.followUpRevision != status.followUpRevision
          || previous.dueFollowUpCount != status.dueFollowUpCount || previous.snoozes != status.snoozes
      }) ?? true {
        followUps.revision += 1
      }
      let changed = status.messageRevision != lastMessageRevision || (lastWorkspaceStatus.map { $0.snoozes != status.snoozes || $0.sendPlans != status.sendPlans } ?? false)
      lastWorkspaceStatus = status
      if changed && !busy.contains("sync") { try await refresh(reloadContent: false) }
      if settings.preferences.realtimeSync == true && !busy.contains("sync") {
        syncSnapshot = try await backend.request("/sync-status", timeout: 8)
      }
    } catch { backend.diagnostics.record("workspace.refresh.failed", RuntimeDiagnostics.errorFields(error)) }
  }

  func previewFile(_ attachment: MailAttachment) {
    requestAttachmentPreview(attachment.id, cached: attachment)
  }

  func previewSourceAttachment(_ id: String) {
    requestAttachmentPreview(id)
  }

  private func requestAttachmentPreview(_ id: String, cached: MailAttachment? = nil) {
    attachmentPreviewRequest?.cancel()
    let revision = restoreRevision
    let queryKey = mailQueryKey
    let selectedId = selectedMessageId
    func current() -> Bool {
      !Task.isCancelled && revision == restoreRevision
        && queryKey == mailQueryKey && selectedId == selectedMessageId
    }
    attachmentPreviewRequest = Task {
      do {
        let attachment: MailAttachment
        if let cached {
          attachment = cached
        } else {
          attachment = try await backend.request("/attachments/\(id)/metadata")
        }
        guard current() else { return }
        let message: MailMessage = try await backend.request("/messages/\(attachment.messageId)")
        guard current() else { return }
        attachmentPreviewIds = message.attachmentIds
        attachmentPreviewIndex = attachmentPreviewIds.firstIndex(of: attachment.id) ?? 0
        previewAttachment = attachment
        cacheAttachment(attachment)
      } catch { if current() { self.error = error.localizedDescription } }
    }
  }

  func openSourceMessage(_ id: String, tab: MailAITab? = nil) {
    sourceMessageRequest?.cancel()
    let source = captureSourceContext()
    let revision = restoreRevision
    func current() -> Bool {
      !Task.isCancelled && revision == restoreRevision
        && source.destination == destination && source.accountId == accountId
        && source.savedSearchID == activeSavedSearchId
        && (source.query == nil || source.query == mailQuery)
        && (source.unified == nil || source.unified == unifiedInbox)
    }
    sourceMessageRequest = Task {
      do {
        let message: MailMessage = try await backend.request("/messages/\(id)")
        guard current() else { return }
        if let draftId = message.draftId {
          editDraft(draftId)
          return
        }
        openMail(message, tab: tab); mailSource = source
      } catch { if current() { self.error = error.localizedDescription } }
    }
  }
  func collectFollowUp(message: MailMessage, title: String? = nil, todo: MailTodo? = nil, sourceKey: String? = nil, snooze: Bool = false) {
    Task {
      var input: [String: Any] = ["messageId": message.id, "title": title ?? todo?.title ?? (message.subject.isEmpty ? "跟进无主题邮件" : message.subject),
        "sourceKey": sourceKey ?? todo.map { "todo:\($0.title)\u{1f}\($0.due)" } ?? "mail:\(message.id)"]
      if let todo { input["todoId"] = todo.id }
      if let item = await followUps.save(input) {
        revealChecklistItem(item.id, accountId: item.accountId, edit: true, snooze: snooze)
      } else { error = followUps.error }
    }
  }
  func revealChecklistItem(_ id: String, accountId: String? = nil, edit: Bool = false, snooze: Bool = false) {
    mailSource = nil
    navigate(.followUps)
    if let accountId {
      self.accountId = accountId
      unifiedInbox = false
    } else {
      unifiedInbox = true
    }
    followUps.setFilter(.all)
    followUps.reveal = .init(followUpId: id, edit: edit, snooze: snooze)
  }
  func signature(for accountId: String) -> String { settings.preferences.accountSignatures?[accountId] ?? settings.preferences.signature }
}
