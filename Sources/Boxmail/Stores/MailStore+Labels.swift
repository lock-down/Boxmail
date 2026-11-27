import BoxmailCore
import Foundation

extension MailStore {
  var mailLabels: [MailCategory] { categories.filter { $0.id != "unclassified" } }

  var labelFilterTitle: String {
    if let listLabelID { return categories.first { $0.id == listLabelID }?.name ?? "标签失效" }
    return listCategory.isEmpty ? "全部标签" : listCategory
  }

  func labels(for message: MailMessage) -> [MailCategory] {
    let members = mailLabels.filter { label in
      if let labels = message.labels { return labels[label.id] != nil }
      return label.name == message.category
    }
    guard let id = listLabelID, let primary = members.first(where: { $0.id == id }) else { return members }
    return [primary] + members.filter { $0.id != id }
  }

  func setLabelFilter(_ id: String?) {
    guard id != listLabelID || !listCategory.isEmpty else { return }
    if id == nil, let source = labelReturnSource, let query = source.query,
      source.accountId == accountId, source.destination == destination, query.accountId == mailQuery.accountId,
      query.query == search, query.filter == filter {
      labelReturnSource = nil
      mailSource = source
      returnToMailSource()
      return
    }
    if listLabelID == nil && id != nil { labelReturnSource = captureSourceContext() }
    if id == nil { labelReturnSource = nil }
    listLabelID = id
    listCategory = ""
  }

  func setLabel(_ label: MailCategory, on messages: [MailMessage], add: Bool) {
    let ids = messages.filter { $0.draftId == nil }.map(\.id)
    guard !ids.isEmpty, !busy.contains("labels") else { return }
    busy.insert("labels")
    mailActionError = nil
    Task {
      defer { busy.remove("labels") }
      do {
        try await backend.perform("/messages/labels", body: ["messageIds": ids, "labelId": label.id, "add": add])
        try await refresh()
      } catch { mailActionError = error.localizedDescription }
    }
  }
}
