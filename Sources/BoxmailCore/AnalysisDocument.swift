import Foundation

public struct AnalysisTable: Hashable {
  public enum Alignment: Hashable { case leading, center, trailing }
  public let headers: [String]
  public let rows: [[String]]
  public let alignments: [Alignment]
}
public struct AnalysisBlock: Identifiable, Hashable {
  public enum Kind: Hashable { case heading, paragraph, listItem, quote, code, table, rule }
  public let id: Int
  public let kind: Kind
  public let text: String
  public var marker = ""
  public var level = 0
  public var checked: Bool?
  public var language = ""
  public var table: AnalysisTable?
}
public enum AnalysisDocument {
  private static let emphasis = try! NSRegularExpression(
    pattern: #"(?<![\\*])(\*{1,3})(?!\*)([^\s*](?:[^*\n]*[^\s*])?)\1(?!\*)"#)

  public static func inlineText(_ source: String) -> AttributedString {
    // Allow Chinese prose to abut emphasis whose text starts or ends in punctuation.
    // Temporary whitespace teaches the parser where the delimiters go without changing the visible text.
    var boundary = "\u{2009}"
    while source.contains(boundary) { boundary += "\u{200A}" }
    func prose(_ value: String) -> String {
      var repaired = "", cursor = value.startIndex
      for match in emphasis.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
        guard let pair = Range(match.range, in: value), let content = Range(match.range(at: 2), in: value) else { continue }
        repaired += value[cursor..<pair.lowerBound]
        if pair.lowerBound > value.startIndex, needsBoundary(value[value.index(before: pair.lowerBound)], value[content.lowerBound]) {
          repaired += boundary
        }
        repaired += value[pair]
        if pair.upperBound < value.endIndex, needsBoundary(value[pair.upperBound], value[value.index(before: content.upperBound)]) {
          repaired += boundary
        }
        cursor = pair.upperBound
      }
      return repaired + value[cursor...]
    }
    let characters = Array(source)
    var normalized = "", plain = "", index = 0
    while index < characters.count {
      if characters[index] != "`" { plain.append(characters[index]); index += 1; continue }
      let start = index
      let count = characters[index...].prefix { $0 == "`" }.count
      var end = index + count, closing: Int?
      while end < characters.count {
        if characters[end] == "`" {
          let run = characters[end...].prefix { $0 == "`" }.count
          if run == count { closing = end + run; break }
          end += run
        } else { end += 1 }
      }
      if let closing {
        normalized += prose(plain) + String(characters[start..<closing]); plain = ""; index = closing
      } else { plain.append(characters[index]); index += 1 }
    }
    normalized += prose(plain)
    guard var rendered = try? AttributedString(markdown: normalized,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return AttributedString(source) }
    while let range = rendered.range(of: boundary) { rendered.removeSubrange(range) }
    return rendered
  }

  private static func needsBoundary(_ neighbor: Character, _ content: Character) -> Bool {
    (neighbor.isLetter || neighbor.isNumber) && (content.isPunctuation || content.isSymbol)
  }

  public static func blocks(_ source: String, interpretLegacyOutline: Bool = true) -> [AnalysisBlock] {
    let original = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    let lines = interpretLegacyOutline ? normalizedLines(original) : original
    var result: [AnalysisBlock] = [], paragraph: [String] = []
    var index = 0
    func flush() {
      if !paragraph.isEmpty {
        result.append(AnalysisBlock(id: result.count, kind: .paragraph, text: paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }
    while index < lines.count {
      let raw = lines[index], line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { flush(); index += 1; continue }
      if let fence = fence(line) {
        flush()
        let language = String(line.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        index += 1
        while index < lines.count {
          let candidate = lines[index].trimmingCharacters(in: .whitespaces)
          if let end = self.fence(candidate), end.character == fence.character, end.count >= fence.count,
            candidate.dropFirst(end.count).trimmingCharacters(in: .whitespaces).isEmpty
          { index += 1; break }
          code.append(lines[index]); index += 1
        }
        result.append(AnalysisBlock(id: result.count, kind: .code, text: code.joined(separator: "\n"), language: language))
        continue
      }
      if let heading = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
        flush()
        let title = String(line[heading.upperBound...]).replacingOccurrences(of: "\\s+#+\\s*$", with: "", options: .regularExpression)
        result.append(AnalysisBlock(id: result.count, kind: .heading, text: title, level: line.prefix { $0 == "#" }.count))
        index += 1; continue
      }
      if index + 1 < lines.count {
        let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
        if underline.count >= 3, Set(underline).count == 1, ["=", "-"].contains(underline.first!),
          !line.hasPrefix("- "), !line.contains("|") {
          flush()
          result.append(AnalysisBlock(id: result.count, kind: .heading, text: line, level: underline.first == "=" ? 1 : 2))
          index += 2; continue
        }
      }
      if isRule(line) {
        flush(); result.append(AnalysisBlock(id: result.count, kind: .rule, text: ""))
        index += 1; continue
      }
      if index + 1 < lines.count, line.contains("|"), let alignments = tableSeparator(lines[index + 1]), cells(line).count == alignments.count {
        flush()
        var rows: [[String]] = []
        let headers = cells(line)
        index += 2
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty, lines[index].contains("|") {
          rows.append(cells(lines[index])); index += 1
        }
        let count = max(headers.count, rows.map(\.count).max() ?? 0)
        func padded(_ row: [String]) -> [String] { row + Array(repeating: "", count: count - row.count) }
        let table = AnalysisTable(headers: padded(headers), rows: rows.map(padded), alignments: alignments + Array(repeating: .leading, count: count - alignments.count))
        result.append(AnalysisBlock(id: result.count, kind: .table, text: "", table: table))
        continue
      }
      if line.hasPrefix(">") {
        flush()
        var quote: [String] = []
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
          let value = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
          quote.append(value.hasPrefix(" ") ? String(value.dropFirst()) : String(value)); index += 1
        }
        result.append(AnalysisBlock(id: result.count, kind: .quote, text: quote.joined(separator: "\n")))
        continue
      }
      if let match = line.range(of: "^(?:[0-9]{1,9}\\.[ \\t]+|[0-9]{1,9}[、)）][ \\t]*|[-+*•][ \\t]+)", options: .regularExpression) {
        flush()
        var value = String(line[match.upperBound...])
        var checked: Bool?
        if let task = value.range(of: "^\\[[ xX]\\]\\s+", options: .regularExpression) {
          checked = value[value.index(after: value.startIndex)] != " "
          value = String(value[task.upperBound...])
        }
        let marker = String(line[match]).trimmingCharacters(in: .whitespaces)
        result.append(AnalysisBlock(id: result.count, kind: .listItem, text: value,
          marker: ["-", "+", "*", "•"].contains(marker) ? "•" : marker,
          level: min(8, raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2), checked: checked))
        index += 1; continue
      }
      paragraph.append(line); index += 1
    }
    flush()
    return result
  }
  private static func fence(_ line: String) -> (character: Character, count: Int)? {
    guard let first = line.first, first == "`" || first == "~" else { return nil }
    let count = line.prefix { $0 == first }.count
    return count >= 3 ? (first, count) : nil
  }
  private static func isRule(_ line: String) -> Bool {
    let value = line.filter { !$0.isWhitespace }
    return value.count >= 3 && Set(value).count == 1 && ["-", "*", "_"].contains(value.first!)
  }
  private static func cells(_ line: String) -> [String] {
    var value = line.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("|") { value.removeFirst() }
    if value.hasSuffix("|"), !value.hasSuffix("\\|") { value.removeLast() }
    var result: [String] = [], cell = "", escaped = false, codeTicks = 0
    let characters = Array(value)
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if escaped {
        cell += character == "|" ? "|" : "\\" + String(character); escaped = false
      } else if character == "\\" { escaped = true
      } else if character == "`" {
        let ticks = characters[index...].prefix { $0 == "`" }.count
        if codeTicks == 0 { codeTicks = ticks } else if codeTicks == ticks { codeTicks = 0 }
        cell += String(repeating: "`", count: ticks); index += ticks - 1
      } else if character == "|" && codeTicks == 0 {
        result.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""
      } else { cell.append(character) }
      index += 1
    }
    if escaped { cell.append("\\") }
    result.append(cell.trimmingCharacters(in: .whitespaces))
    return result
  }
  private static func tableSeparator(_ line: String) -> [AnalysisTable.Alignment]? {
    let values = cells(line)
    guard !values.isEmpty, values.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { return nil }
    return values.map { $0.hasSuffix(":") ? $0.hasPrefix(":") ? .center : .trailing : .leading }
  }
  private static func normalizedLines(_ lines: [String]) -> [String] {
    let headings = "文件主题|主要结论|关键数字和日期|关键数字与日期|关键数据|注意事项|需要关注的问题|行动建议|摘要"
    var activeFence: (character: Character, count: Int)?
    var result: [String] = []
    for raw in lines {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if let fence = fence(line) {
        if let active = activeFence {
          if fence.character == active.character && fence.count >= active.count, line.dropFirst(fence.count).trimmingCharacters(in: .whitespaces).isEmpty { activeFence = nil }
        } else { activeFence = fence }
        result.append(raw); continue
      }
      if activeFence != nil || line.contains("|") || line.hasPrefix(">") { result.append(raw); continue }
      var normalized = raw.replacingOccurrences(
        of: "^[ \\t]*(?:\\*\\*(\(headings))(?:\\*\\*[：:]|[：:]\\*\\*)|(\(headings))[：:])[ \\t]*",
        with: "\n\n## $1$2\n", options: .regularExpression)
      if !normalized.contains("*") && !normalized.contains("`") {
        normalized = normalized.replacingOccurrences(of: "(?<=[。；;：:])([0-9]{1,2}[)）])[ \\t]*",
          with: "\n$1 ", options: .regularExpression)
      }
      result += normalized.components(separatedBy: "\n")
    }
    return result
  }
}
