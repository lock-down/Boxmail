import AppKit
import BoxmailCore
import SwiftUI

struct MailChange {
  let title: String
  let undo: [MailUndoItem]
}

extension MailStore {
  var mailActionInProgress: Bool { busy.contains("mail-batch") }
  var selectedMails: [MailMessage] {
    filteredMessages.filter { selectedMessageIds.contains($0.id) && $0.draftId == nil }
  }
  var isMailWorkspace: Bool {
    !search.isEmpty || [.inbox, .starred, .sent, .trash, .archive].contains(destination)
  }

  func reconcileMailSelection() {
    // An overview can open a mail before the destination page has loaded.
    // An empty/stale page must not erase that explicit navigation target.
    guard pageKey == mailQueryKey else { return }
    if selectionQueryKey != mailQueryKey {
      selectedMessageIds = []
      selectionQueryKey = mailQueryKey
    }
    selectedMessageIds.formIntersection(Set(filteredMessages.map(\.id)))
    if selectedMessageIds.isEmpty, let id = selectedMessageId,
      filteredMessages.contains(where: { $0.id == id }) {
      selectedMessageIds = [id]
    }
    if !selectedMessageIds.contains(selectedMessageId ?? "") {
      selectedMessageId = filteredMessages.first { selectedMessageIds.contains($0.id) }?.id
      mailAITab = nil
    }
  }

  func setMailSelection(_ ids: Set<String>, for queryKey: String) {
    // Native List may still send a callback from a view that is being replaced.
    guard queryKey == mailQueryKey, pageKey == queryKey, !mailActionInProgress else { return }
    if let request = mailRevealRequest, ids != [request.messageId] { mailRevealRequest = nil }
    let entries = filteredMessages.filter { ids.contains($0.id) }
    selectedMessageIds = Set(entries.filter { entries.count == 1 || $0.draftId == nil }.map(\.id))
    selectionQueryKey = queryKey
    applyMailSelection()
  }

  func applyMailSelection() {
    guard pageKey == mailQueryKey, selectionQueryKey == mailQueryKey, !mailActionInProgress else { return }
    let selected = filteredMessages.filter { selectedMessageIds.contains($0.id) }
    if selected.count == 1, let message = selected.first {
      select(message)
    } else if !selected.contains(where: { $0.id == selectedMessageId }) {
      selectedMessageId = selected.first?.id
      mailAITab = nil
    }
  }

  func selectAllLoadedMail() {
    setMailSelection(Set(filteredMessages.filter { $0.draftId == nil }.map(\.id)), for: mailQueryKey)
  }

  func clearMailSelection() {
    mailRevealRequest = nil
    selectedMessageIds = []
    selectedMessageId = nil
    mailAITab = nil
  }

  func updateMessages(_ messages: [MailMessage], changes: [String: Any]) {
    let updates = messages.filter { $0.draftId == nil }.map { ["id": $0.id, "changes": changes] as [String: Any] }
    let title: String
    if let folder = changes["folder"] as? String {
      title = folder == "trash" ? "已移到已删除" : folder == "archive" ? "已归档" : "已移动"
    } else if let unread = changes["unread"] as? Bool {
      title = unread ? "已标记未读" : "已标记已读"
    } else if let starred = changes["starred"] as? Bool {
      title = starred ? "已添加星标" : "已取消星标"
    } else { title = "已更新分类" }
    performMailUpdates(updates, title: title)
  }

  func restoreMessages(_ messages: [MailMessage]) {
    let updates = messages.filter { $0.folder == "trash" || $0.folder == "archive" }.map {
      ["id": $0.id, "changes": ["folder": ($0.folder == "trash" ? $0.restoreFolder : $0.unarchiveFolder) ?? "inbox"]] as [String: Any]
    }
    performMailUpdates(updates, title: "已恢复邮件")
  }

  func undoMailChange() {
    guard let change = mailChange, !change.undo.isEmpty else { return }
    performMailUpdates(change.undo.map(\.payload), title: "已撤销操作", undoing: true)
  }

  private func performMailUpdates(_ updates: [[String: Any]], title: String, undoing: Bool = false) {
    guard !updates.isEmpty, !mailActionInProgress else { return }
    busy.insert("mail-batch")
    mailActionError = nil
    Task {
      defer { busy.remove("mail-batch") }
      do {
        let result: MailBatchResponse = try await BackendService.shared.request(
          "/messages/batch", method: "POST", body: ["updates": updates])
        if result.changedCount == 0 && !undoing {
          if mailChange == nil { mailChange = MailChange(title: "邮件状态无需更改", undo: []) }
          return
        }
        // Once committed, keep the undo even if refreshing the view fails.
        mailUndoManager?.removeAllActions(withTarget: self)
        mailChange = MailChange(title: result.changedCount == 0 ? "邮件状态无需更改"
          : "\(title) · \(result.changedCount) 封", undo: undoing ? [] : result.undo)
        do { try await refresh() }
        catch { mailActionError = "操作已保存，列表刷新未完成，请重新加载。" }
        if !undoing && !result.undo.isEmpty {
          mailUndoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.undoMailChange() }
          }
          mailUndoManager?.setActionName("邮件操作")
        }
      } catch {
        mailActionError = error.localizedDescription
      }
    }
  }
}

struct MailTriageFocusKey: FocusedValueKey { typealias Value = MailStore }
extension FocusedValues {
  var mailTriage: MailStore? {
    get { self[MailTriageFocusKey.self] }
    set { self[MailTriageFocusKey.self] = newValue }
  }
}
