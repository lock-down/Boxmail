import BoxmailCore
import Foundation

struct PendingConfigurationImport: Identifiable {
  let id = UUID()
  let archive: ConfigurationArchive
  let plan: ConfigurationImportPlan
  let fileName: String
  func containsCredential(_ logical: String) -> Bool {
    let value: String
    if logical == "ai-key" { value = archive.credentials.aiKey }
    else if logical.hasPrefix("ai-provider-") {
      value = archive.credentials.aiProviderKeys?[String(logical.dropFirst("ai-provider-".count))] ?? ""
    } else if let account = plan.accounts.first(where: { logical == "mail-\($0.accountId)" }) {
      value = archive.credentials.mailPasswords[account.sourceId] ?? ""
    } else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  func credentialDisposition(_ logical: String) -> String {
    if containsCredential(logical) { return "使用文件中提供的新凭证" }
    if plan.credentialsRequired?.contains(logical) == true { return "地址或身份已改变，导入后需重新填写凭证" }
    return "未提供新凭证；仅在地址和身份一致时保留本机凭证（如有）"
  }
}

struct ConfigurationImportOutcome {
  let refreshed: Bool
  let credentialsRequired: [String]
}

@MainActor enum ConfigurationTransferService {
  static func export(to url: URL) async throws -> ConfigurationArchive {
    let snapshot: ConfigurationSnapshot = try await BackendService.shared.request(
      "/configuration/export", method: "POST", body: [:])
    let archive = try ConfigurationTransfer.export(snapshot: snapshot,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版",
      readCredential: { try CredentialService.read($0) })
    try await Task.detached(priority: .userInitiated) { try archive.write(to: url) }.value
    return archive
  }

  static func inspect(_ url: URL) async throws -> PendingConfigurationImport {
    let archive = try await Task.detached(priority: .userInitiated) { try ConfigurationArchive.read(from: url) }.value
    let plan: ConfigurationImportPlan = try await BackendService.shared.request(
      "/configuration/inspect", method: "POST", body: ["configuration": try jsonObject(archive.configuration)])
    return PendingConfigurationImport(archive: archive, plan: plan, fileName: url.lastPathComponent)
  }

  /// New credential items let an unsuccessful import leave all existing secrets intact.
  /// The database commits account/settings changes and their references together.
  static func apply(_ candidate: PendingConfigurationImport, store: MailStore) async throws -> ConfigurationImportOutcome {
    let applied = try await ConfigurationTransfer.apply(archive: candidate.archive, plan: candidate.plan,
      saveCredential: { reference, value in try CredentialService.save(value, account: reference) },
      removeCredential: { try? CredentialService.save("", account: $0) },
      commit: { references in
        try await BackendService.shared.request("/configuration/import", method: "POST", body: [
          "configuration": try jsonObject(candidate.archive.configuration),
          "accounts": candidate.plan.accounts.map { ["sourceId": $0.sourceId, "accountId": $0.accountId] },
          "revision": candidate.plan.revision, "credentialReferences": references, "approved": true,
        ])
      }, current: {
        let state: AppSnapshot = try await BackendService.shared.request("/state?compact=1", timeout: 10)
        return ConfigurationSnapshot(accounts: state.accounts, settings: state.settings,
          credentialsRequired: candidate.plan.credentialsRequired?.filter { !candidate.containsCredential($0) })
      })
    // Use the committed response before refreshing mail lists. A refresh failure
    // must not leave editable settings pointing at the pre-import values.
    store.accounts = applied.accounts
    store.settings = applied.settings
    CredentialService.useReferences(applied.settings.credentialReferences ?? [:])
    store.credentialIssueAccounts.subtract(candidate.plan.accounts.map(\.accountId))
    let required = applied.credentialsRequired ?? []
    store.credentialIssueAccounts.formUnion(required.filter { $0.hasPrefix("mail-") }.map { String($0.dropFirst(5)) })
    do {
      try await store.refresh()
      store.restoreRevision += 1
      return ConfigurationImportOutcome(refreshed: true, credentialsRequired: required)
    } catch {
      store.restoreRevision += 1
      return ConfigurationImportOutcome(refreshed: false, credentialsRequired: required)
    }
  }
}
