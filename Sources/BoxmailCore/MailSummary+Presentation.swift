import Foundation

extension MailSummary {
  public var overviewText: String {
    let text = overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? points.joined(separator: " ") : text
  }
  public var plainText: String {
    var sections = ["内容概要：\(overviewText)"]
    let pending = todos.map { todo in
      "\(todo.done ? "[x]" : "[ ]") \(todo.title)" + (todo.due.isEmpty ? "" : "（\(todo.due)）")
    }
    sections.append("待处理：\n" + (pending.isEmpty ? "暂无明确待办。" : pending.joined(separator: "\n")))
    if let nextSteps, !nextSteps.isEmpty { sections.append("您可继续：\n" + nextSteps.map { "- \($0.title)" }.joined(separator: "\n")) }
    if !keyInfo.isEmpty { sections.append("关键信息：\n" + keyInfo.map { "\($0.label)：\($0.value)" }.joined(separator: "\n")) }
    return sections.joined(separator: "\n\n")
  }
}
