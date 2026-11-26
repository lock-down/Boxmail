import BoxmailCore
import Foundation

struct ActivityHistoryEntry: Identifiable {
  let events: [AuditEvent]
  var id: String { events[0].id }
}

enum ActivityPresentation {
  static func syncAccount(_ event: AuditEvent, accounts: [MailAccount]) -> MailAccount? {
    guard event.type == "sync" else { return nil }
    return accounts.first { event.detail.hasPrefix($0.email + "：") }
  }

  static func isUnchangedSync(_ event: AuditEvent) -> Bool {
    event.type == "sync" && event.detail.hasSuffix("：新增 0 封，补齐 0 封正文，跳过 0 个邮件")
  }

  static func history(_ events: [AuditEvent]) -> [ActivityHistoryEntry] {
    var entries: [ActivityHistoryEntry] = []
    var unchanged: [String: Int] = [:]
    for event in events {
      if isUnchangedSync(event), let index = unchanged[event.detail] {
        entries[index] = ActivityHistoryEntry(events: entries[index].events + [event])
      } else {
        if isUnchangedSync(event) { unchanged[event.detail] = entries.count }
        entries.append(ActivityHistoryEntry(events: [event]))
      }
    }
    return entries
  }

  static func title(_ event: AuditEvent) -> String {
    let parts = event.detail.split(maxSplits: 1, whereSeparator: { $0 == ":" || $0 == "：" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let statuses = ["completed": "已完成", "needsApproval": "待确认", "failed": "未完成",
      "running": "正在处理", "paused": "已暂停", "partial": "部分完成", "applied": "已应用", "undone": "已撤销"]
    if parts.count == 2, taskTitle(parts[0]) != parts[0], let status = statuses[parts[1]] {
      return taskTitle(parts[0]) + status
    }
    return event.detail
  }

  static func taskTitle(_ task: String) -> String {
    ["summary": "邮件总结", "reply": "AI 回复", "compose": "AI 写信",
      "classify": "邮件整理", "mailOrganization": "清单整理", "labelMatch": "试用标签", "attachment": "附件理解", "translate": "邮件翻译",
      "question": "邮件问答", "compare": "附件比较", "searchPlan": "搜索条件",
      "archiveSummary": "资料包总览", "conversationSummary": "会话总结", "conversationReply": "会话回复"][task] ?? task
  }

  static func icon(_ event: AuditEvent) -> AppicaGlyph {
    switch event.type {
    case "send": .send
    case "send-warning": .alertTriangle
    case "sync": .clock
    case "draft": .edit
    case "agent": .sparkles
    case "organize": .folder
    default: .clock
    }
  }
}
