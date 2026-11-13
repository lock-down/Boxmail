import BoxmailCore
import Foundation
import Observation

struct AttachmentPageRequest: Hashable {
  static let pageSize = 50
  let accountId, query, type, sort: String
  let ascending: Bool
  let offset: Int
  var path: String {
    var components = URLComponents()
    components.queryItems = [
      .init(name: "accountId", value: accountId), .init(name: "q", value: query),
      .init(name: "type", value: type), .init(name: "sort", value: sort),
      .init(name: "direction", value: ascending ? "asc" : "desc"),
      .init(name: "offset", value: String(offset)),
      .init(name: "limit", value: String(Self.pageSize)),
    ]
    return "/attachments?"
      + (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
  }
}

extension AttachmentPageRequest: PagedRequest {
  func sameFilters(as other: Self) -> Bool {
    accountId == other.accountId && query == other.query && type == other.type
      && sort == other.sort && ascending == other.ascending
  }
}

@Observable @MainActor final class AttachmentPageStore {
  private let paging: PagedListStore<AttachmentPageRequest, AttachmentPage>
  @ObservationIgnored private var loadedFilters:
    (query: String, type: String, sort: [KeyPathComparator<AttachmentPageItem>])?
  var accountId: String { didSet { if accountId != oldValue { paging.resetOffset() } } }
  var query = "" { didSet { if query != oldValue { paging.resetOffset() } } }
  var type = "全部" { didSet { if type != oldValue { paging.resetOffset() } } }
  var sortOrder = [KeyPathComparator(\AttachmentPageItem.date, order: .reverse)] {
    didSet { if sortOrder != oldValue { paging.resetOffset() } }
  }
  init(backend: BackendService, accountId: String) {
    self.paging = PagedListStore(backend: backend)
    self.accountId = accountId
  }
  var request: AttachmentPageRequest {
    let sort: String
    switch sortOrder.first?.keyPath {
    case \AttachmentPageItem.name: sort = "name"
    case \AttachmentPageItem.size: sort = "size"
    default: sort = "date"
    }
    let types = [
      "PDF": "pdf", "Word": "word", "表格": "spreadsheet", "PPT": "presentation",
      "TXT": "text", "图片": "image", "ZIP": "archive",
    ]
    return .init(
      accountId: accountId, query: query, type: types[type] ?? "all", sort: sort,
      ascending: sortOrder.first?.order == .forward, offset: paging.offset)
  }
  var page: AttachmentPage? { paging.page }
  var loadedRequest: AttachmentPageRequest? { paging.loadedRequest }
  var loading: Bool { paging.loading }
  var error: String? { paging.error }
  var offset: Int { paging.offset }
  var visiblePage: AttachmentPage? { loadedRequest?.accountId == accountId ? page : nil }
  var items: [AttachmentPageItem] { visiblePage?.items ?? [] }
  var showsPreviousPage: Bool { visiblePage != nil && loadedRequest != request }
  var canPrevious: Bool { paging.canPrevious(showsPreviousPage: showsPreviousPage) }
  var canNext: Bool { paging.canAdvance(showsPreviousPage: showsPreviousPage) }
  func previous() { if canPrevious { paging.goPrevious() } }
  func next() { if canNext { paging.goNext() } }
  var canRestoreLoadedPage: Bool { !loading && showsPreviousPage && error != nil }
  func restoreLoadedPage() {
    guard canRestoreLoadedPage, let loadedRequest, loadedRequest.accountId == accountId,
      let loadedFilters
    else { return }
    query = loadedFilters.query
    type = loadedFilters.type
    sortOrder = loadedFilters.sort
    paging.restore(loadedRequest)
  }
  func load(revision: Int, force: Bool = false) async {
    let key = request
    let filters = (query: query, type: type, sort: sortOrder)
    await paging.load(
      key, revision: revision, force: force,
      delay: key.query.isEmpty ? nil : .milliseconds(180), current: { self.request },
      onSuccess: { _ in self.loadedFilters = filters })
  }
}
