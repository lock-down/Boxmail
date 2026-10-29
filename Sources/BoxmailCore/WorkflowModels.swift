import Foundation

public struct MailCategory: Codable, Identifiable, Hashable {
  public var id, name, description: String
  public static var defaults: [MailCategory] {
    ["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来", "未分类"].map {
      MailCategory(id: $0 == "未分类" ? "unclassified" : $0, name: $0, description: "")
    }
  }
}
public struct CategoryResponse: Codable { public var categories: [MailCategory] }
public struct ContactSuggestion: Codable, Identifiable, Hashable {
  public var email, name, lastUsed: String
  public var frequency: Int
  public var id: String { email }
}
public struct ContactsResponse: Codable { public var contacts: [ContactSuggestion] }
public struct MailConversation: Codable {
  public var id, accountId: String
  public var messages: [MailMessage]
  public var total: Int
  public var nextOffset: Int?
  public var partial: Bool
}
public struct SearchIndexStatus: Codable {
  public var indexed, cached, pending, version: Int
  public var failed: Int?
  public var updatedAt: String?
  public var partial: Bool
}
public struct SearchCondition: Codable { public var field, value: String }
public struct ParsedSearch: Codable { public var terms: [String]; public var conditions: [SearchCondition] }
public struct BackupSummary: Codable {
  public var createdAt: String
  public var counts: [String: Int]
  public var totalBytes: Int
  public var credentialsIncluded: Bool
  public var sha256, path, previousBackup: String?
  public var credentialsRequired: [String]?
}

public enum RecipientCompletion {
  public struct Segment: Equatable {
    public var range: NSRange
    public var query: String
  }
  public static func segment(in text: String, caret: Int) -> Segment {
    let source = text as NSString
    let caret = min(max(0, caret), source.length)
    var quoted = false, escaped = false, angle = false, separators: [Int] = [-1]
    for index in 0..<source.length {
      let char = source.character(at: index)
      if escaped { escaped = false; continue }
      if char == 92 && quoted { escaped = true }
      else if char == 34 { quoted.toggle() }
      else if !quoted && char == 60 { angle = true }
      else if !quoted && char == 62 { angle = false }
      else if !quoted && !angle && [44, 59, 65292, 65307].contains(Int(char)) { separators.append(index) }
    }
    let start = (separators.last { $0 < caret } ?? -1) + 1
    let end = separators.first { $0 >= caret } ?? source.length
    let range = NSRange(location: start, length: end - start)
    let query = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "")
    return Segment(range: range, query: query)
  }
  public static func addresses(in values: [String]) -> Set<String> {
    let expression = try! NSRegularExpression(pattern: #"[^\s,;<>\"，；]+@[^\s,;<>\"，；]+\.[^\s,;<>\"，；]+"#)
    return Set(values.flatMap { value in
      expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        .map { (value as NSString).substring(with: $0.range).lowercased() }
    })
  }
  public static func replacing(_ text: String, segment: Segment, name: String, email: String) -> (text: String, caret: Int) {
    let source = text as NSString
    let cleanName = name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    let escaped = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let address = name.isEmpty || name.lowercased() == email.lowercased() ? email : "\"\(escaped)\" <\(email)>"
    let hasSuffix = NSMaxRange(segment.range) < source.length
    let value = (segment.range.location > 0 ? " " : "") + address + (hasSuffix ? "" : ", ")
    return (source.replacingCharacters(in: segment.range, with: value), segment.range.location + (value as NSString).length)
  }
}
