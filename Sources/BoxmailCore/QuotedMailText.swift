import Foundation

public enum QuotedMailText {
  public static func split(_ text: String) -> (visible: String, quoted: String) {
    let lines = text.components(separatedBy: "\n")
    let pattern = #"(?i)^\s*(>|On .+wrote:|在.+写道[:：]|-{2,}\s*(original message|原始邮件)|发件人\s*[:：])"#
    guard let index = lines.firstIndex(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else {
      return (text, "")
    }
    return (lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
      lines[index...].joined(separator: "\n"))
  }
  public static func hasHTMLQuote(_ html: String?) -> Bool {
    html?.range(of: #"(?i)<blockquote\b|\b(gmail_quote|yahoo_quoted)\b"#, options: .regularExpression) != nil
  }
}
