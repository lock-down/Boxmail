import Foundation

enum RecipientTextBlock {
  case text(String)
  case recipients([RecipientField])

  static func split(_ text: String) -> [Self] {
    let lines = text.components(separatedBy: "\n")
    let header = try! NSRegularExpression(pattern: #"^\s*(?:[>*-]\s*)*(收件人|抄送|密送|To|Cc|Bcc)\s*[:：]\s*(.*)$"#, options: .caseInsensitive)
    var result: [Self] = [], pending: [String] = []
    var index = 0
    while index < lines.count {
      let line = lines[index]
      guard let match = header.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
        let labelRange = Range(match.range(at: 1), in: line), let valueRange = Range(match.range(at: 2), in: line)
      else { pending.append(line); index += 1; continue }
      let label = line[labelRange].lowercased()
      let kind: RecipientField.Kind = ["cc", "抄送"].contains(label) ? .cc : ["bcc", "密送"].contains(label) ? .bcc : .to
      var sourceLines = [line], values = [String(line[valueRange])]
      index += 1
      while index < lines.count, lines[index].first?.isWhitespace == true,
        lines[index].contains("@"), !lines[index].contains(":"), !lines[index].contains("：") {
        sourceLines.append(lines[index]); values.append(lines[index]); index += 1
      }
      let value = values.joined(separator: "\n")
      guard value.utf16.count > 600 || value.filter({ $0 == "@" }).count > 8 else {
        pending += sourceLines; continue
      }
      if !pending.isEmpty { result.append(.text(pending.joined(separator: "\n"))); pending = [] }
      let field = RecipientField(kind: kind, value: value)
      if case .recipients(let fields) = result.last {
        result[result.count - 1] = .recipients(fields + [field])
      } else { result.append(.recipients([field])) }
    }
    if !pending.isEmpty { result.append(.text(pending.joined(separator: "\n"))) }
    return result
  }
}
