import BoxmailCore
import Foundation

extension MailStore {
  var supportsUnifiedScope: Bool { [.inbox, .starred, .sent, .archive, .spam, .trash].contains(destination) }
  var mailQuery: MailQuery {
    .init(accountId: (unifiedInbox && supportsUnifiedScope) || (!search.isEmpty && searchAllAccounts) ? nil : accountId,
      folder: [.followUps, .rules, .outbox, .attachments, .organize].contains(destination) ? "inbox" : destination.rawValue, query: search, filter: filter, category: listCategory.isEmpty ? nil : listCategory, labelId: listLabelID)
  }
  var scopeTitle: String {
    unifiedInbox && (supportsUnifiedScope || destination == .followUps) ? "所有账户" : currentAccount?.sidebarName ?? "邮箱"
  }
  func loadSavedSearches() async {
    let revision = restoreRevision
    do {
      let views: [SavedSearch] = try await backend.request("/saved-searches")
      if !Task.isCancelled, revision == restoreRevision { savedSearches = views }
    } catch {
      if !Task.isCancelled, revision == restoreRevision { self.error = error.localizedDescription }
    }
  }
  func saveSearch(name: String, updating id: String? = nil) async {
    let revision = restoreRevision
    do {
      let saved: SavedSearch = try await backend.request("/saved-searches" + (id.map { "/\($0)" } ?? ""), method: "POST",
        body: ["name": name, "query": try jsonObject(mailQuery)])
      guard revision == restoreRevision else { return }
      activeSavedSearchId = saved.id
      await loadSavedSearches()
    } catch { if revision == restoreRevision { self.error = error.localizedDescription } }
  }
  func openSavedSearch(_ saved: SavedSearch) {
    mailSource = nil; mailAITab = nil
    let query = saved.query
    if let account = query.accountId { accountId = account }
    unifiedInbox = query.accountId == nil
    searchAllAccounts = query.accountId == nil
    let target = MailDestination(rawValue: query.folder) ?? .inbox
    destination = target == .summary ? .followUps : target
    search = query.query; filter = query.filter; listCategory = query.category ?? ""
    listLabelID = query.labelId
    labelReturnSource = nil
    activeSavedSearchId = saved.id
  }
  func removeSavedSearch(_ id: String) async {
    let revision = restoreRevision
    do {
      try await backend.perform("/saved-searches/\(id)", method: "DELETE")
      guard revision == restoreRevision else { return }
      if activeSavedSearchId == id { activeSavedSearchId = nil }
      await loadSavedSearches()
    } catch { if revision == restoreRevision { self.error = error.localizedDescription } }
  }
}
