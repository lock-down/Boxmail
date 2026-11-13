import BoxmailCore
import Foundation
import Observation

struct OrganizationPageRequest: Hashable {
  static let pageSize = 50
  let accountId, category: String
  let offset: Int
  var path: String {
    var components = URLComponents()
    components.queryItems = [
      .init(name: "accountId", value: accountId), .init(name: "category", value: category),
      .init(name: "offset", value: String(offset)),
      .init(name: "limit", value: String(Self.pageSize)),
    ]
    return "/organization/messages?"
      + (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
  }
}

extension OrganizationPageRequest: PagedRequest {
  func sameFilters(as other: Self) -> Bool {
    accountId == other.accountId && category == other.category
  }
}

@Observable @MainActor final class OrganizationPageStore {
  private let paging: PagedListStore<OrganizationPageRequest, OrganizationPage>
  var accountId: String { didSet { if accountId != oldValue { paging.resetOffset() } } }
  var category = "" { didSet { if category != oldValue { paging.resetOffset() } } }
  init(backend: BackendService, accountId: String) {
    self.paging = PagedListStore(backend: backend)
    self.accountId = accountId
  }
  var request: OrganizationPageRequest {
    .init(accountId: accountId, category: category, offset: paging.offset)
  }
  var page: OrganizationPage? { paging.page }
  var loadedRequest: OrganizationPageRequest? { paging.loadedRequest }
  var loading: Bool { paging.loading }
  var error: String? { paging.error }
  var offset: Int { paging.offset }
  var visiblePage: OrganizationPage? { loadedRequest?.accountId == accountId ? page : nil }
  var showsPreviousPage: Bool { visiblePage != nil && loadedRequest != request }
  var canPrevious: Bool { paging.canPrevious(showsPreviousPage: showsPreviousPage) }
  var canNext: Bool { paging.canAdvance(showsPreviousPage: showsPreviousPage) }
  func previous() { if canPrevious { paging.goPrevious() } }
  func next() { if canNext { paging.goNext() } }
  var canRestoreLoadedPage: Bool { !loading && showsPreviousPage && error != nil }
  func restoreLoadedPage() {
    guard canRestoreLoadedPage, let loadedRequest, loadedRequest.accountId == accountId else {
      return
    }
    category = loadedRequest.category
    paging.restore(loadedRequest)
  }
  func load(revision: Int, force: Bool = false) async {
    await paging.load(request, revision: revision, force: force, current: { self.request })
  }
}
