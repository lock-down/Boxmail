import BoxmailCore
import Foundation
import Observation

protocol PagedRequest: Hashable {
  static var pageSize: Int { get }
  var accountId: String { get }
  var offset: Int { get }
  var path: String { get }
  func sameFilters(as other: Self) -> Bool
}

protocol PagedResponse: Decodable {
  var offset: Int { get }
  var limit: Int { get }
  var total: Int { get }
}

extension AttachmentPage: PagedResponse {}
extension OrganizationPage: PagedResponse {}

/// Shared generation-ticket, caching and failure-rollback rules for paged lists.
@Observable @MainActor final class PagedListStore<Request: PagedRequest, Page: PagedResponse> {
  @ObservationIgnored private let backend: BackendService
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var loadedRevision: Int?
  private(set) var page: Page?
  private(set) var loadedRequest: Request?
  private(set) var loading = false
  private(set) var error: String?
  private(set) var offset = 0

  init(backend: BackendService) { self.backend = backend }

  func resetOffset() { offset = 0 }
  func goPrevious() { if offset > 0 { offset = max(0, offset - Request.pageSize) } }
  func goNext() { offset += Request.pageSize }
  func restore(_ loaded: Request) {
    offset = loaded.offset
    error = nil
    generation = UUID()
  }
  func canPrevious(showsPreviousPage: Bool) -> Bool {
    !loading && !showsPreviousPage && offset > 0
  }
  func canAdvance(showsPreviousPage: Bool) -> Bool {
    !loading && !showsPreviousPage && (page.map { $0.offset + $0.limit < $0.total } == true)
  }

  func load(
    _ key: Request, revision: Int, force: Bool = false, delay: Duration? = nil,
    current: () -> Request, onSuccess: ((Request) -> Void)? = nil
  ) async {
    if !force, loadedRequest == key, loadedRevision == revision { return }
    let ticket = UUID()
    generation = ticket
    loading = true
    error = nil
    defer { if generation == ticket { loading = false } }
    do {
      if let delay { try await Task.sleep(for: delay) }
      let response: Page = try await backend.request(key.path)
      try Task.checkCancellation()
      guard generation == ticket, key == current() else { return }
      offset = response.offset
      page = response
      loadedRequest = current()
      loadedRevision = revision
      onSuccess?(key)
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled, (error as NSError).code != NSURLErrorCancelled,
        generation == ticket, key == current()
      else { return }
      self.error = error.localizedDescription
      if let loadedRequest, loadedRequest.sameFilters(as: key) {
        offset = loadedRequest.offset
      }
    }
  }
}
