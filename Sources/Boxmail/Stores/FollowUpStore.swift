import BoxmailCore
import Foundation
import Observation

enum ChecklistFilter: String, CaseIterable {
  case all, mine, waiting, snoozed, completed, due, removed

  var title: String {
    switch self {
    case .all: "全部"
    case .mine: "待我处理"
    case .waiting: "等待对方"
    case .snoozed: "已延后"
    case .completed: "已完成"
    case .due: "已到期"
    case .removed: "已移除摘要"
    }
  }
}

struct ChecklistRequest: PagedRequest {
  static let pageSize = 50
  let accountId: String
  let unified: Bool
  let filter: ChecklistFilter
  let offset: Int
  let followUpId: String?

  var path: String {
    var url = URLComponents()
    url.path = "/checklist"
    var query = [URLQueryItem(name: "filter", value: filter.rawValue),
      URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: String(Self.pageSize))]
    if !unified { query.append(URLQueryItem(name: "accountId", value: accountId)) }
    if let followUpId { query.append(URLQueryItem(name: "followUpId", value: followUpId)) }
    url.queryItems = query
    return url.string ?? "/checklist"
  }

  func sameFilters(as other: Self) -> Bool {
    accountId == other.accountId && unified == other.unified && filter == other.filter
  }
}

extension ChecklistPage: PagedResponse {}

struct ChecklistReveal: Equatable {
  let followUpId: String
  var edit = false
  var snooze = false
}

@Observable @MainActor final class FollowUpStore {
  let scrollPosition = ScrollPositionState()
  let pages: PagedListStore<ChecklistRequest, ChecklistPage>
  private let backend: BackendService
  var error: String?
  var reveal: ChecklistReveal?
  var selectedId: String?
  var filter: ChecklistFilter = .all
  var revision = 0
  var dismissedItem: FollowUp?
  private(set) var mutating: Set<String> = []

  init(backend: BackendService) {
    self.backend = backend
    pages = PagedListStore(backend: backend)
  }

  func setFilter(_ value: ChecklistFilter) {
    filter = value
    resetPosition()
  }

  func resetPosition() {
    pages.resetOffset()
    scrollPosition.origin = .zero
    selectedId = nil
    reveal = nil
    error = nil
  }

  @discardableResult func save(_ input: [String: Any], id: String? = nil) async -> FollowUp? {
    await save(input, path: "/follow-ups" + (id.map { "/\($0)" } ?? ""))
  }

  @discardableResult func update(_ item: ChecklistItem, in row: ChecklistRow, _ input: [String: Any]) async -> FollowUp? {
    let key = row.id + "\u{1f}" + item.id
    guard mutating.insert(key).inserted else { return nil }
    defer { mutating.remove(key) }
    if let id = item.followUp?.id { return await save(input, id: id) }
    guard let todoId = item.todoId else { return nil }
    var body = input
    body["todoId"] = todoId
    body["messageId"] = row.messageId
    body["accountId"] = row.accountId
    return await save(body, path: "/checklist/suggestions")
  }

  func isMutating(_ item: ChecklistItem, in row: ChecklistRow) -> Bool {
    mutating.contains(row.id + "\u{1f}" + item.id)
  }

  private func save(_ input: [String: Any], path: String) async -> FollowUp? {
    do {
      let item: FollowUp = try await backend.request(path, method: "POST", body: input)
      error = nil
      revision += 1
      return item
    } catch { self.error = error.localizedDescription; return nil }
  }

  func remove(_ item: FollowUp) async {
    do {
      try await backend.perform("/follow-ups/\(item.id)", method: "DELETE")
      error = nil
      revision += 1
    }
    catch { self.error = error.localizedDescription }
  }
}
