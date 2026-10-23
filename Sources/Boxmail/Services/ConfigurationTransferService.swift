import BoxmailCore
import Foundation

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
    let archive = try ConfigurationTransfer.export(snapshot: snapshot,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版",
      readCredential: { try KeychainService.read($0) })
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
    let applied = try await ConfigurationTransfer.apply(archive: candidate.archive, plan: candidate.plan,
      saveCredential: { reference, value in try KeychainService.save(value, account: reference) },
      removeCredential: { try? KeychainService.save("", account: $0) },
      commit: { references in
        try await BackendService.shared.request("/configuration/import", method: "POST", body: [
          "configuration": try jsonObject(candidate.archive.configuration),
          "accounts": candidate.plan.accounts.map { ["sourceId": $0.sourceId, "accountId": $0.accountId] },
          "revision": candidate.plan.revision, "credentialReferences": references, "approved": true,
        ])
      }, current: {
        let state: AppSnapshot = try await BackendService.shared.request("/state?compact=1", timeout: 10)
        return ConfigurationSnapshot(accounts: state.accounts, settings: state.settings)
      })
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
}
