import Foundation

public enum CredentialRequirements {
  public static func notice(_ required: [String], accounts: [MailAccount], ai: AIConfig) -> String? {
    guard !required.isEmpty else { return nil }
    let labels = Array(Set(required)).sorted().map { key in
      if key.hasPrefix("mail-") {
        let id = String(key.dropFirst(5))
        let account = accounts.first { $0.id == id }
        return "邮箱授权码：\(account?.email ?? id)（设置 > 账号）"
      }
      guard key == "ai-key" || key.hasPrefix("ai-provider-") else { return "凭证：\(key)（设置中重新填写）" }
      let id = key == "ai-key" ? "default" : String(key.dropFirst("ai-provider-".count))
      let provider = ai.providers.first { $0.id == id }
      return "API Key：\(provider?.name ?? (key == "ai-key" ? "默认 AI 服务商" : id))（设置 > AI 助手）"
    }
    return "请重新填写以下凭证：\n" + labels.joined(separator: "\n")
  }
}
