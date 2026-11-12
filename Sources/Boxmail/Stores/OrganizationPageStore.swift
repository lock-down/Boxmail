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

@Observable @MainActor final class OrganizationPageStore {
  @ObservationIgnored private let backend: BackendService
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var loadedRevision: Int?
  private(set) var page: OrganizationPage?
  private(set) var loadedRequest: OrganizationPageRequest?
  private(set) var loading = false
  private(set) var error: String?
  var accountId: String { didSet { if accountId != oldValue { offset = 0 } } }
  var category = "" { didSet { if category != oldValue { offset = 0 } } }
  private(set) var offset = 0

  init(backend: BackendService, accountId: String) {
    self.backend = backend
    self.accountId = accountId
  }
  var request: OrganizationPageRequest {
    .init(accountId: accountId, category: category, offset: offset)
  }
  var visiblePage: OrganizationPage? { loadedRequest?.accountId == accountId ? page : nil }
  var showsPreviousPage: Bool { visiblePage != nil && loadedRequest != request }
  var canPrevious: Bool { !loading && !showsPreviousPage && offset > 0 }
  var canNext: Bool {
    !loading && !showsPreviousPage && visiblePage.map { $0.offset + $0.limit < $0.total } == true
  }
  var canRestoreLoadedPage: Bool { !loading && showsPreviousPage && error != nil }
  func previous() { if canPrevious { offset = max(0, offset - OrganizationPageRequest.pageSize) } }
  func next() { if canNext { offset += OrganizationPageRequest.pageSize } }
  func restoreLoadedPage() {
    guard canRestoreLoadedPage, let loadedRequest, loadedRequest.accountId == accountId else {
      return
    }
    category = loadedRequest.category
    offset = loadedRequest.offset
    error = nil
    generation = UUID()
  }
  func load(revision: Int, force: Bool = false) async {
    let key = request
    if !force, loadedRequest == key, loadedRevision == revision { return }
    let ticket = UUID()
    generation = ticket
    loading = true
    error = nil
    defer { if generation == ticket { loading = false } }
    do {
      let response: OrganizationPage = try await backend.request(key.path)
      try Task.checkCancellation()
      guard generation == ticket, key == request else { return }
      offset = response.offset
      page = response
      loadedRequest = request
      loadedRevision = revision
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled, (error as NSError).code != NSURLErrorCancelled,
        generation == ticket, key == request
      else { return }
      self.error = error.localizedDescription
      if let loadedRequest, loadedRequest.accountId == key.accountId,
        loadedRequest.category == key.category
      {
        offset = loadedRequest.offset
      }
    }
  }
}
