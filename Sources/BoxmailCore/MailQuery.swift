import Foundation

public struct MailQuery: Codable, Hashable {
  public var accountId: String?
  public var folder: String
  public var query: String
  public var filter: String
  public var category: String?
  public init(accountId: String?, folder: String = "inbox", query: String = "", filter: String = "全部", category: String? = nil) {
    self.accountId = accountId; self.folder = folder; self.query = query
    self.filter = filter; self.category = category
  }
  public var queryItems: [URLQueryItem] {
    [.init(name: "accountId", value: accountId), .init(name: "folder", value: folder),
      .init(name: "q", value: query), .init(name: "filter", value: filter),
      .init(name: "category", value: category)]
  }
  public var key: String { [accountId ?? "*", folder, query, filter, category ?? ""].map { "\($0.utf8.count):\($0)" }.joined() }
}

public struct SavedSearch: Codable, Identifiable, Hashable {
  public var id, name: String
  public var query: MailQuery
}
