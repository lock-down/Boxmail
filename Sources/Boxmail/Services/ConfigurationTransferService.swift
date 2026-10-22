import BoxmailCore
import Foundation

struct ConfigurationImportPlan: Decodable {
  struct Account: Decodable, Identifiable {
    let sourceId, accountId, name, email: String
    let existing: Bool
    var id: String { sourceId }
  }
  let revision: String
  let accounts: [Account]
}

struct PendingConfigurationImport: Identifiable {
  let id = UUID()
  let archive: ConfigurationArchive
  let plan: ConfigurationImportPlan
  let fileName: String
}

@MainActor enum ConfigurationTransferService {
  static func export(to url: URL) async throws -> ConfigurationArchive {
    let snapshot: ConfigurationSnapshot = try await BackendService.shared.request(
      "/configuration/export", method: "POST", body: [:])
    var passwords: [String: String] = [:]
    for account in snapshot.accounts { passwords[account.id] = try KeychainService.read("mail-\(account.id)") }
    let credentials = ConfigurationCredentials(mailPasswords: passwords, aiKey: try KeychainService.read("ai-key"))
    let archive = ConfigurationArchive(configuration: snapshot, credentials: credentials,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")
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
  static func apply(_ candidate: PendingConfigurationImport, store: MailStore) async throws -> Bool {
    var references: [String: String] = [:]
    var values = ["ai-key": candidate.archive.credentials.aiKey]
    for account in candidate.plan.accounts {
      values["mail-\(account.accountId)"] = candidate.archive.credentials.mailPasswords[account.sourceId] ?? ""
    }
    do {
      for (logical, value) in values {
        let reference = "configuration-\(UUID().uuidString)"
        try KeychainService.save(value, account: reference)
        references[logical] = reference
      }
    } catch { discard(references); throw error }
    let applied: ConfigurationSnapshot
    do {
      applied = try await BackendService.shared.request("/configuration/import", method: "POST", body: [
        "configuration": try jsonObject(candidate.archive.configuration),
        "accounts": candidate.plan.accounts.map { ["sourceId": $0.sourceId, "accountId": $0.accountId] },
        "revision": candidate.plan.revision, "credentialReferences": references, "approved": true,
      ])
    } catch {
      let original = error
      let state: AppSnapshot
      do { state = try await BackendService.shared.request("/state?compact=1", timeout: 10) }
      catch {
        // A lost response can follow a committed transaction. Retain staged items
        // until the next snapshot resolves the result rather than deleting live keys.
        throw BackendService.shared.failure("暂时无法确认导入结果，请重新打开 Boxmail 检查配置后再操作。")
      }
      guard references.allSatisfy({ state.settings.credentialReferences?[$0.key] == $0.value }) else {
        discard(references); throw original
      }
      applied = ConfigurationSnapshot(accounts: state.accounts, settings: state.settings)
    }
    // Use the committed response before refreshing mail lists. A refresh failure
    // must not leave editable settings pointing at the pre-import values.
    store.accounts = applied.accounts
    store.settings = applied.settings
    KeychainService.useReferences(applied.settings.credentialReferences ?? [:])
    store.credentialAuthorizationAccounts.subtract(candidate.plan.accounts.map(\.accountId))
    do {
      try await store.refresh()
      store.restoreRevision += 1
      return true
    } catch {
      store.restoreRevision += 1
      return false
    }
  }

  private static func discard(_ references: [String: String]) {
    for reference in references.values { try? KeychainService.save("", account: reference) }
  }
}
