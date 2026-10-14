import Foundation

public struct MailAccount: Codable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var email: String
  public var username: String
  public var imapHost: String
  public var imapPort: Int
  public var imapTLS: Bool
  public var smtpHost: String
  public var smtpPort: Int
  public var smtpTLS: Bool
  public var lastSync: String?
  public var isDemo: Bool
  public init(
    id: String = UUID().uuidString, name: String = "", email: String = "", username: String = "",
    imapHost: String = "", imapPort: Int = 993, imapTLS: Bool = true, smtpHost: String = "",
    smtpPort: Int = 465, smtpTLS: Bool = true, lastSync: String? = nil, isDemo: Bool = false
  ) {
    self.id = id
    self.name = name
    self.email = email
    self.username = username
    self.imapHost = imapHost
    self.imapPort = imapPort
    self.imapTLS = imapTLS
    self.smtpHost = smtpHost
    self.smtpPort = smtpPort
    self.smtpTLS = smtpTLS
    self.lastSync = lastSync
    self.isDemo = isDemo
  }
}
public struct MailMessage: Codable, Identifiable, Hashable {
  public var id, accountId, folder, sender, senderEmail, to, cc, subject, body, preview, date,
    category: String
  public var unread, starred: Bool
  public var attachmentIds: [String]
  public var summary: MailSummary?
  public var messageId: String?
  public var html: String?
  public var hasRemoteImages: Bool?
  public var bodyVersion: Int?
  public var uid: Int?
}
public struct MailSummary: Codable, Hashable {
  public var points: [String]
  public var todos: [MailTodo]
  public var keyInfo: [KeyInfo]
}
public struct MailTodo: Codable, Identifiable, Hashable {
  public var id, title, due: String
  public var done: Bool
}
public struct KeyInfo: Codable, Hashable { public var label, value: String }
public struct MailAttachment: Codable, Identifiable, Hashable {
  public var id, messageId, name, contentType, path, text, parseError, date: String
  public var size: Int
  public var analysis: String?
  public var isImage: Bool {
    ["jpg", "jpeg", "png", "gif", "webp"].contains((name as NSString).pathExtension.lowercased())
      || ["image/jpeg", "image/png", "image/gif", "image/webp"].contains(contentType)
  }
  public var isPDF: Bool {
    (name as NSString).pathExtension.lowercased() == "pdf" || contentType == "application/pdf"
  }
  public var canAnalyze: Bool {
    isImage || isPDF || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
public struct MailDraft: Codable, Identifiable, Hashable {
  public var id, accountId, to, cc, bcc, subject, body, status, updatedAt: String
  public var attachmentIds: [String]
  public var inReplyTo, sourceMessageId: String?
  public init(accountId: String, to: String = "", subject: String = "", body: String = "") {
    id = UUID().uuidString
    self.accountId = accountId
    self.to = to
    cc = ""
    bcc = ""
    self.subject = subject
    self.body = body
    status = "draft"
    updatedAt = ISO8601DateFormatter().string(from: Date())
    attachmentIds = []
  }
}
public struct AIConfig: Codable, Hashable {
  public var baseURL = "https://api.deepseek.com", model = "deepseek-flash"
  public var effort = "high"
  public var timeout = 120
  public var enabled = true
  public var prompts: [String: String] = AIPromptDefaults.values
  public init() {}
}
public struct Preferences: Codable, Hashable {
  public var syncMinutes = 5, fontSize = 14
  public var markRead = true, launchAtLogin = false, notifications = false,
    blockRemoteImages = true, spamFilter = true
  public var signature = "", language = "简体中文"
  public init() {}
}
public struct SettingsData: Codable {
  public var id = "settings"
  public var ai = AIConfig()
  public var preferences = Preferences()
  public init() {}
}
public struct AgentJob: Codable, Identifiable {
  public var id, task, status, createdAt: String
  public var messageId, error, accountId: String?
  public var result: AgentResult?
}
public struct AgentResult: Codable {
  public var subject, body, draftId, text: String?
  public var items: [Classification]?
}
public struct Classification: Codable, Identifiable { public var id, category, reason: String }
public struct AuditEvent: Codable, Identifiable { public var id, time, type, detail: String }
public struct AppSnapshot: Codable {
  public var accounts: [MailAccount]
  public var messages: [MailMessage]
  public var drafts: [MailDraft]
  public var attachments: [MailAttachment]
  public var jobs: [AgentJob]
  public var settings: SettingsData
  public var events: [AuditEvent]
  public var pendingMutations: Int
}
public enum MailDestination: String, CaseIterable, Identifiable {
  case inbox, starred, drafts, sent, attachments, trash, summary, replies, organize, analysis,
    archive
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .inbox: return "收件箱"
    case .starred: return "星标邮件"
    case .drafts: return "草稿箱"
    case .sent: return "已发送"
    case .attachments: return "附件中心"
    case .trash: return "已删除"
    case .summary: return "AI 总结"
    case .replies: return "自动回复"
    case .organize: return "智能整理"
    case .analysis: return "附件解析"
    case .archive: return "已归档"
    }
  }
  public var icon: String {
    switch self {
    case .inbox: return "tray"
    case .starred: return "star"
    case .drafts: return "square.and.pencil"
    case .sent: return "paperplane"
    case .attachments: return "paperclip"
    case .trash: return "trash"
    case .summary: return "sparkles"
    case .replies: return "arrowshape.turn.up.left.2"
    case .organize: return "wand.and.stars"
    case .analysis: return "doc.text.magnifyingglass"
    case .archive: return "archivebox"
    }
  }
  public var isAI: Bool { [.summary, .replies, .organize, .analysis].contains(self) }
}
