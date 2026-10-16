import Foundation

public struct AnalysisBlock: Identifiable, Hashable {
  public enum Kind: Hashable { case heading, paragraph, listItem }
  public let id: Int
  public let kind: Kind
  public let text: String
  public let marker: String
}

public enum AnalysisDocument {
  public static func blocks(_ source: String) -> [AnalysisBlock] {
    let headings = "文件主题|主要结论|关键数字和日期|关键数字与日期|关键数据|注意事项|需要关注的问题|行动建议|摘要"
    var text = source.replacingOccurrences(of: "\r\n", with: "\n")
    text = text.replacingOccurrences(
      of: "(?m)^[ \\t]*(?:\\*\\*)?(\(headings))(?:\\*\\*)?[：:][ \\t]*",
      with: "\n\n## $1\n", options: .regularExpression)
    text = text.replacingOccurrences(
      of: "(?<=[\\s。；;：:])([0-9]{1,2}[)）])[ \\t]*", with: "\n$1 ", options: .regularExpression)
    var result: [AnalysisBlock] = []
    var paragraph: [String] = []
    func append(_ kind: AnalysisBlock.Kind, _ value: String, marker: String = "") {
      result.append(AnalysisBlock(id: result.count, kind: kind, text: value, marker: marker))
    }
    func flush() {
      if !paragraph.isEmpty {
        append(.paragraph, paragraph.joined(separator: "\n"))
        paragraph = []
      }
    }
    for raw in text.components(separatedBy: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flush()
        continue
      }
      if let match = line.range(of: "^#{1,6}\\s+", options: .regularExpression) {
        flush()
        append(.heading, String(line[match.upperBound...]))
        continue
      }
      if let match = line.range(
        of: "^(?:[0-9]{1,2}[.、)）][ \\t]*|[-*•][ \\t]+)", options: .regularExpression)
      {
        flush()
        let marker = String(line[match]).trimmingCharacters(in: .whitespaces)
        append(.listItem, String(line[match.upperBound...]), marker: marker)
        continue
      }
      paragraph.append(line)
    }
    flush()
    return result
  }
}
