import Foundation
import Testing
@testable import BoxmailCore

@Test func backupCredentialRequirementsDecodeAndIdentifyTheAffectedAccountsAndProviders() throws {
  let raw = #"{"createdAt":"2026-10-28T00:00:00Z","counts":{},"totalBytes":0,"credentialsIncluded":false,"credentialsRequired":["ai-key","mail-a","ai-provider-work"]}"#
  let summary = try JSONDecoder().decode(BackupSummary.self, from: Data(raw.utf8))
  var ai = AIConfig()
  ai.providers.append(.init(id: "work", name: "工作服务商", baseURL: "https://work.example.test"))
  let accounts = [MailAccount(id: "a", email: "reader@example.test")]
  let notice = try #require(CredentialRequirements.notice(summary.credentialsRequired ?? [], accounts: accounts, ai: ai))
  #expect(notice.contains("邮箱授权码：reader@example.test"))
  #expect(notice.contains(ai.providers[0].name) && notice.contains("工作服务商"))
  #expect(notice.contains("设置 > 账号") && notice.contains("设置 > AI 助手"))
  let legacy = #"{"createdAt":"2026-10-28T00:00:00Z","counts":{},"totalBytes":0,"credentialsIncluded":false}"#
  let decoded = try JSONDecoder().decode(BackupSummary.self, from: Data(legacy.utf8))
  #expect(decoded.counts.isEmpty)
  #expect(decoded.credentialsRequired == nil)
  #expect(CredentialRequirements.notice([], accounts: accounts, ai: ai) == nil)
}
