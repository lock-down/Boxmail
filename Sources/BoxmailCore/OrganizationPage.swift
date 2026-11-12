import Foundation

public struct OrganizationPage: Codable {
  public let items: [MailMessage]
  public let total, offset, limit, accountTotal: Int
  public let categoryCounts: [OrganizationCategoryCount]
}

public struct OrganizationCategoryCount: Codable {
  public let name: String
  public let count: Int
}
