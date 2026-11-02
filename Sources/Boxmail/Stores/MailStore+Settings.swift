import BoxmailCore
import Foundation

extension MailStore {
  /// A refresh failure must not turn a committed settings save into a false failure.
  func saveSettings(
    ai: AIConfig, preferences: Preferences, keys: [String: String] = [:],
    credentialStorage: EnvCredentialStore? = nil
  ) async throws -> Bool {
    let saved: SettingsData = try await CredentialService.commit(
      values: keys, storage: credentialStorage,
      operation: { references in
        try await self.backend.request(
          "/settings", method: "POST",
          body: [
            "ai": try jsonObject(ai), "preferences": try jsonObject(preferences),
            "credentialReferences": references,
          ])
      },
      current: {
        let state: SettingsSnapshot = try await self.backend.request("/state?compact=1&previews=0")
        return (state.settings, state.settings.credentialReferences ?? [:])
      })
    settings = saved
    CredentialService.useReferences(saved.credentialReferences ?? [:])
    do {
      try await refresh()
      return true
    } catch { return false }
  }

  func saveAccount(
    _ account: MailAccount, password: String, credentialStorage: EnvCredentialStore? = nil
  ) async throws -> Bool {
    let saved: AccountSettingsSnapshot = try await CredentialService.commit(
      values: ["mail-\(account.id)": password], storage: credentialStorage,
      operation: { references in
        try await self.backend.request(
          "/accounts", method: "POST",
          body: ["account": try jsonObject(account), "credentialReferences": references])
      },
      current: {
        let state: AccountSettingsState = try await self.backend.request(
          "/state?compact=1&previews=0")
        guard let account = state.accounts.first(where: { $0.id == account.id }) else {
          throw self.backend.failure("邮箱账户未保存。")
        }
        return (
          .init(account: account, settings: state.settings),
          state.settings.credentialReferences ?? [:]
        )
      })
    if let index = accounts.firstIndex(where: { $0.id == saved.account.id }) {
      accounts[index] = saved.account
    } else {
      accounts.append(saved.account)
    }
    settings = saved.settings
    CredentialService.useReferences(settings.credentialReferences ?? [:])
    credentialIssueAccounts.remove(saved.account.id)
    accountId = saved.account.id
    do { try await refresh(); return true } catch { return false }
  }
}

private struct SettingsSnapshot: Decodable { let settings: SettingsData }
private struct AccountSettingsSnapshot: Decodable {
  let account: MailAccount
  let settings: SettingsData
}
private struct AccountSettingsState: Decodable {
  let accounts: [MailAccount]
  let settings: SettingsData
}
