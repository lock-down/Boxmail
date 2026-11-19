import Foundation

public struct FollowUp: Codable, Identifiable, Hashable {
  public var id, accountId, messageId, conversationId, sourceKey, title, state, dueText, subject, createdAt, updatedAt: String
  public var dueAt, snoozedUntil, waitingSince, notifiedAt, replyMessageId: String?
  public var reminderCancelled: Bool
  public var effectiveDate: Date? { (snoozedUntil ?? dueAt).flatMap { MailTimestamp.date($0) } }
  public var isSnoozed: Bool { snoozedUntil != nil && effectiveDate.map { $0 > Date() } == true }
  public var isDue: Bool { state != "completed" && !reminderCancelled && effectiveDate.map { $0 <= Date() } == true }
}
public struct SendPlan: Codable, Identifiable, Hashable {
  public var id, draftId, accountId, subject, to, scheduledAt, timeZone, revision, status, createdAt: String
  public var error, warning, completedAt: String?
  public var rejected: [String]?
  public var canChange: Bool { ["waiting", "failed", "paused"].contains(status) }
}
public struct RuleActions: Codable, Hashable {
  public var category: String?
  public var starred, unread, archive, summary, attachments, followUp, reply: Bool?
  public init() {}
  public var description: String {
    var values: [String] = []
    if let category { values.append("分类为\(category)") }
    if let starred { values.append(starred ? "添加星标" : "取消星标") }
    if let unread { values.append(unread ? "标记未读" : "标记已读") }
    if archive == true { values.append("归档") }
    if summary == true { values.append("总结") }
    if attachments == true { values.append("附件理解") }
    if followUp == true { values.append("跟进建议") }
    if reply == true { values.append("回复预览") }
    return values.joined(separator: "、")
  }
}
public struct MailRule: Codable, Identifiable, Hashable {
  public var id, name, intent, createdAt, revision: String
  public var query: MailQuery
  public var actions: RuleActions
  public var enabled, automatic: Bool
  public init(accountId: String?) {
    id = ""; name = ""; intent = ""; createdAt = ""; revision = ""
    query = .init(accountId: accountId); actions = .init(); enabled = true; automatic = false
  }
}
public struct RuleRun: Codable, Identifiable, Equatable {
  public var id, ruleId, name, revision, createdAt, status: String
  public var query: MailQuery
  public var actions: RuleActions
  public var automatic: Bool?
  public var error: String?
  public var items: [RuleRunItem]
}
public struct RuleRunItem: Codable, Identifiable, Equatable {
  public var id, accountId, subject, status, reason: String
  public var error: String?
  public var jobIds: [String]
  public var suggestions: [MailTodo]
}
public struct AIUsage: Codable, Identifiable, Equatable {
  public var id, task, provider, model, startedAt, status: String
  public var taskId: String?
  public var durationMs: Int
  public var input, output, cacheRead, cacheWrite, cost: Double?
}
public struct WritingStyle: Codable, Identifiable, Hashable {
  public var id, name, instruction: String
}
public struct AssistantScope: Codable, Hashable {
  public var kind: String
  public var messageId: String?
  public var query: MailQuery?
  public var attachmentIds: [String]?
  public var relationship: String?
  public init(kind: String, messageId: String? = nil, query: MailQuery? = nil, attachmentIds: [String]? = nil, relationship: String? = nil) {
    self.kind = kind; self.messageId = messageId; self.query = query
    self.attachmentIds = attachmentIds; self.relationship = relationship
  }
}
public struct AssistantSession: Codable, Identifiable {
  public var id, createdAt: String
  public var scope: AssistantScope
  public var turns: [AssistantTurn]
}
public struct AssistantTurn: Codable, Identifiable {
  public var id, prompt, text, createdAt: String
  public var scope: AssistantScope
  public var sources: [AssistantSource]
  public var citations: [AssistantCitation]
  public var actions: [AssistantAction]
  public var contextCoverage: AssistantContextCoverage?
}
public struct AssistantContextCoverage: Codable, Hashable {
  public var total, included: Int
  public var partial: Bool
}
public struct AssistantSource: Codable, Identifiable {
  public var id, accountId, subject, sender, date: String
  public var coverage: MailAIContext
}
public struct AssistantCitation: Codable, Hashable {
  public var messageId: String
  public var attachmentId: String?
}
public struct AssistantAction: Codable, Identifiable {
  public var id, kind, status: String
  public var messageIds: [String]
  public var category, title: String?
}
public enum WorkspaceStatus {
  public static func title(_ status: String) -> String {
    ["waiting": "等待发送", "submitting": "正在提交", "sent": "已发送", "failed": "失败", "uncertain": "结果不确定",
      "cancelled": "已取消", "paused": "已暂停", "running": "处理中", "completed": "已完成", "partial": "部分未完成",
      "undone": "已撤销状态变更", "preview": "待审阅", "pending": "待处理", "existing": "已处理", "interrupted": "已中断" ][status] ?? status
  }
}
