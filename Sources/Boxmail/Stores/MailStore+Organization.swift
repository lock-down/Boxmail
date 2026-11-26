import BoxmailCore
import Foundation

struct MailOrganizationPolicy: Decodable {
  let id, mode: String
  let labelRules: [String: String]
  let point: InboxPoint?

  struct InboxPoint: Decodable {
    let path, validity: String
    let uidNext: Int
  }
}

extension MailStore {
  func organizationPolicy(for accountID: String) async throws -> MailOrganizationPolicy {
    try await backend.request(organizationPath("policy", accountID: accountID))
  }

  func saveOrganizationPolicy(_ input: [String: Any]) async throws -> MailOrganizationPolicy {
    try await backend.request("/mail-organization/policy", method: "POST", body: input)
  }

  func organizationPath(_ operation: String, accountID: String, query: String? = nil, offset: Int? = nil) -> String {
    var url = URLComponents()
    url.path = "/mail-organization/\(operation)"
    url.queryItems = [URLQueryItem(name: "accountId", value: accountID), URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "offset", value: offset.map(String.init))]
    return url.string ?? url.path
  }
}
