import BoxmailCore
import Foundation

extension MailStore {
  var supportsUnifiedScope: Bool { [.inbox, .starred, .sent, .archive, .spam, .trash].contains(destination) }
  var mailQuery: MailQuery {
    .init(accountId: (unifiedInbox && supportsUnifiedScope) || (!search.isEmpty && searchAllAccounts) ? nil : accountId,
      folder: [.followUps, .rules, .outbox, .attachments, .organize].contains(destination) ? "inbox" : destination.rawValue, query: search, filter: filter, category: listCategory.isEmpty ? nil : listCategory)
  }
  var scopeTitle: String { unifiedInbox && supportsUnifiedScope ? "所有账户" : currentAccount?.sidebarName ?? "邮箱" }
  func loadSavedSearches() async {
    do { savedSearches = try await backend.request("/saved-searches") }
    catch { self.error = error.localizedDescription }
  }
  func saveSearch(name: String, updating id: String? = nil) async {
    do {
      let saved: SavedSearch = try await backend.request("/saved-searches" + (id.map { "/\($0)" } ?? ""), method: "POST",
        body: ["name": name, "query": try jsonObject(mailQuery)])
      activeSavedSearchId = saved.id
      await loadSavedSearches()
    } catch { self.error = error.localizedDescription }
  }
  func openSavedSearch(_ saved: SavedSearch) {
    mailSource = nil; mailAITab = nil
    let query = saved.query
    if let account = query.accountId { accountId = account }
    unifiedInbox = query.accountId == nil
    searchAllAccounts = query.accountId == nil
    destination = MailDestination(rawValue: query.folder) ?? .inbox
    search = query.query; filter = query.filter; listCategory = query.category ?? ""
    activeSavedSearchId = saved.id
  }
  func removeSavedSearch(_ id: String) async {
    do {
      try await backend.perform("/saved-searches/\(id)", method: "DELETE")
      if activeSavedSearchId == id { activeSavedSearchId = nil }
      await loadSavedSearches()
    } catch { self.error = error.localizedDescription }
  }
}
