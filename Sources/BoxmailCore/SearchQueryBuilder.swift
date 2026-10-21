import Foundation

public enum SearchQueryBuilder {
  public static func quoted(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
  public static func make(terms: [String], conditions: [(String, String)]) -> String {
    (terms.filter { !$0.isEmpty }.map(quoted)
      + conditions.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { "\($0.0):\(quoted($0.1.trimmingCharacters(in: .whitespacesAndNewlines)))" }).joined(separator: " ")
  }
}
