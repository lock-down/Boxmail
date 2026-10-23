import BoxmailCore
import Foundation

struct SummaryReplyRequest: Identifiable {
  let id = UUID()
  let messageId, prompt: String
}

struct SummaryListChange {
  let accountId: String
  let messageIds: [String]
  let hidden: Bool
}
private struct SummaryVisibilityResponse: Decodable { let messageIds: [String] }

extension MailStore {
  var summaryOverviewMessages: [MailMessage] {
    accountMessages.filter(\.isInSummaryOverview).sorted { $0.date > $1.date }
  }
  var removedSummaryMessages: [MailMessage] {
    accountMessages.filter { $0.summary != nil && $0.summaryHidden == true && $0.folder != "trash" }
      .sorted { $0.date > $1.date }
  }
  var changingSummaryList: Bool { busy.contains("summary-list-\(accountId)") }

  func setSummaryVisibility(ids: [String] = [], hidden: Bool, all: Bool = false,
    for requestedAccount: String? = nil, undo: Bool = false) {
    let requestedAccount = requestedAccount ?? accountId
    let operation = "summary-list-\(requestedAccount)"
    guard !busy.contains(operation), all || !ids.isEmpty else { return }
    busy.insert(operation)
    summaryListError = nil
    Task {
      defer { busy.remove(operation) }
      do {
        var body: [String: Any] = ["accountId": requestedAccount, "hidden": hidden]
        if all { body["all"] = true } else { body["messageIds"] = ids }
        let result: SummaryVisibilityResponse = try await BackendService.shared.request(
          "/summaries/visibility", method: "POST", body: body)
        if undo { summaryListChange = nil }
        else if !result.messageIds.isEmpty {
          summaryListChange = SummaryListChange(accountId: requestedAccount, messageIds: result.messageIds, hidden: hidden)
        }
        try await refresh()
      } catch {
        if self.accountId == requestedAccount { summaryListError = error.localizedDescription }
        try? await refresh()
      }
    }
  }

  func undoSummaryListChange() {
    guard let change = summaryListChange else { return }
    setSummaryVisibility(ids: change.messageIds, hidden: !change.hidden, for: change.accountId, undo: true)
  }

  func followSummary(_ step: SummaryNextStep, in message: MailMessage) {
    guard !busy.contains("agent") else { return }
    switch step.action {
    case "reply":
      guard !step.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      summaryReplyRequest = SummaryReplyRequest(messageId: message.id, prompt: step.prompt)
      openMail(message, tab: .reply)
      generate(task: "reply", message: message, prompt: step.prompt, preview: true)
    case "attachments":
      guard !message.attachmentIds.isEmpty else { return }
      attachmentResultsMessageId = message.id
      openMail(message, tab: .attachment)
      let batch = attachmentBatch(for: message)
      if let batch, ["paused", "failed", "partial"].contains(batch.status) {
        analyzeAttachments(in: message, retry: batch)
      } else if attachments.contains(where: { $0.messageId == message.id && $0.canAnalyze && !$0.isAnalyzed }) {
        analyzeAttachments(in: message)
      }
    default: break
    }
  }
}
