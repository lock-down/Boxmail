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

@Observable @MainActor final class AttachmentPageStore {
  @ObservationIgnored private let backend: BackendService
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var loadedRevision: Int?
  @ObservationIgnored private var loadedFilters:
    (query: String, type: String, sort: [KeyPathComparator<AttachmentPageItem>])?
  private(set) var page: AttachmentPage?
  private(set) var loadedRequest: AttachmentPageRequest?
  private(set) var loading = false
  private(set) var error: String?
  var accountId: String { didSet { if accountId != oldValue { offset = 0 } } }
  var query = "" { didSet { if query != oldValue { offset = 0 } } }
  var type = "全部" { didSet { if type != oldValue { offset = 0 } } }
  var sortOrder = [KeyPathComparator(\AttachmentPageItem.date, order: .reverse)] {
    didSet { if sortOrder != oldValue { offset = 0 } }
  }
  private(set) var offset = 0
  init(backend: BackendService, accountId: String) {
    self.backend = backend
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
      ascending: sortOrder.first?.order == .forward, offset: offset)
  }
  var visiblePage: AttachmentPage? { loadedRequest?.accountId == accountId ? page : nil }
  var items: [AttachmentPageItem] { visiblePage?.items ?? [] }
  var showsPreviousPage: Bool { visiblePage != nil && loadedRequest != request }
  var canPrevious: Bool { !loading && !showsPreviousPage && offset > 0 }
  var canNext: Bool {
    !loading && !showsPreviousPage && visiblePage.map { $0.offset + $0.limit < $0.total } == true
  }
  func previous() { if canPrevious { offset = max(0, offset - AttachmentPageRequest.pageSize) } }
  func next() { if canNext { offset += AttachmentPageRequest.pageSize } }
  var canRestoreLoadedPage: Bool { !loading && showsPreviousPage && error != nil }
  func restoreLoadedPage() {
    guard canRestoreLoadedPage, let loadedRequest, loadedRequest.accountId == accountId,
      let loadedFilters
    else { return }
    query = loadedFilters.query
    type = loadedFilters.type
    sortOrder = loadedFilters.sort
    offset = loadedRequest.offset
    error = nil
    generation = UUID()
  }
  func load(revision: Int, force: Bool = false) async {
    let key = request
    let filters = (query: query, type: type, sort: sortOrder)
    if !force, loadedRequest == key, loadedRevision == revision { return }
    let ticket = UUID()
    generation = ticket
    loading = true
    error = nil
    defer { if generation == ticket { loading = false } }
    do {
      if !key.query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
      let response: AttachmentPage = try await backend.request(key.path)
      try Task.checkCancellation()
      guard generation == ticket, key == request else { return }
      offset = response.offset
      page = response
      loadedRequest = request
      loadedFilters = filters
      loadedRevision = revision
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled, (error as NSError).code != NSURLErrorCancelled,
        generation == ticket, key == request
      else { return }
      self.error = error.localizedDescription
      if let loadedRequest, loadedRequest.accountId == key.accountId,
        loadedRequest.query == key.query, loadedRequest.type == key.type,
        loadedRequest.sort == key.sort, loadedRequest.ascending == key.ascending
      {
        offset = loadedRequest.offset
      }
    }
  }
}
