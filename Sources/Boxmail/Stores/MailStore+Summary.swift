import BoxmailCore
import Foundation

struct SummaryListChange {
  let accountId: String
  let messageIds: [String]
  let hidden: Bool
}
private struct SummaryVisibilityResponse: Decodable { let messageIds: [String] }

extension MailStore {
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
        let result: SummaryVisibilityResponse = try await self.backend.request(
          "/summaries/visibility", method: "POST", body: body)
        if undo { summaryListChange = nil }
        else if !result.messageIds.isEmpty {
          summaryListChange = SummaryListChange(accountId: requestedAccount, messageIds: result.messageIds, hidden: hidden)
        }
        try await refresh()
      } catch {
        if self.accountId == requestedAccount || destination == .followUps && unifiedInbox {
          summaryListError = error.localizedDescription
        }
        try? await refresh()
      }
    }
  }

  func undoSummaryListChange() {
    guard let change = summaryListChange else { return }
    setSummaryVisibility(ids: change.messageIds, hidden: !change.hidden, for: change.accountId, undo: true)
  }
}
