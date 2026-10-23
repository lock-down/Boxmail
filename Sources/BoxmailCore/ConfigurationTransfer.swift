import Foundation

public struct ConfigurationImportPlan: Decodable {
  public struct Account: Decodable, Identifiable {
    public let sourceId, accountId, name, email: String
    public let existing: Bool
    public var id: String { sourceId }
    public init(sourceId: String, accountId: String, name: String, email: String, existing: Bool) {
      self.sourceId = sourceId; self.accountId = accountId; self.name = name; self.email = email; self.existing = existing
    }
  }
  public let revision: String
  public let accounts: [Account]
  public init(revision: String, accounts: [Account]) { self.revision = revision; self.accounts = accounts }
}

@MainActor public enum ConfigurationTransfer {
  public static func export(snapshot: ConfigurationSnapshot, appVersion: String,
    readCredential: (String) throws -> String) throws -> ConfigurationArchive {
    if let issue = snapshot.settings.ai.validationIssue { throw failure(issue) }
    var passwords: [String: String] = [:]
    for account in snapshot.accounts { passwords[account.id] = try readCredential("mail-\(account.id)") }
    var aiKey = "", providerKeys: [String: String] = [:]
    for provider in snapshot.settings.ai.providers {
      let value = try readCredential(provider.credentialAccount)
      if provider.id == "default" { aiKey = value } else { providerKeys[provider.id] = value }
    }
    return try ConfigurationArchive(configuration: snapshot,
      credentials: .init(mailPasswords: passwords, aiKey: aiKey, aiProviderKeys: providerKeys),
      appVersion: appVersion).validated()
  }

  public static func apply(archive: ConfigurationArchive, plan: ConfigurationImportPlan,
    saveCredential: (String, String) throws -> Void,
    removeCredential: (String) -> Void,
    commit: ([String: String]) async throws -> ConfigurationSnapshot,
    current: () async throws -> ConfigurationSnapshot) async throws -> ConfigurationSnapshot {
    let archive = try archive.validated()
    let sourceIDs = Set(archive.configuration.accounts.map(\.id))
    guard plan.accounts.count == sourceIDs.count,
      Set(plan.accounts.map(\.sourceId)) == sourceIDs,
      Set(plan.accounts.map(\.accountId)).count == plan.accounts.count,
      plan.accounts.allSatisfy({ $0.accountId.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil }) else {
      throw failure("配置导入的账号映射无效，请重新选择配置文件。")
    }
    var values: [String: String] = [:]
    for provider in archive.configuration.settings.ai.providers {
      values[provider.credentialAccount] = provider.id == "default" ? archive.credentials.aiKey : archive.credentials.aiProviderKeys?[provider.id]
    }
    for account in plan.accounts { values["mail-\(account.accountId)"] = archive.credentials.mailPasswords[account.sourceId] }
    var references: [String: String] = [:]
    do {
      for logical in values.keys.sorted() {
        let reference = "configuration-\(UUID().uuidString)"
        try saveCredential(reference, values[logical]!)
        references[logical] = reference
      }
    } catch {
      for reference in references.values { removeCredential(reference) }
      throw error
    }
    do { return try await commit(references) }
    catch {
      let original = error
      let state: ConfigurationSnapshot
      do { state = try await current() }
      catch {
        // A missing response may follow a committed transaction. Keep its possible live keys.
        throw failure("暂时无法确认导入结果，请重新打开 Boxmail 检查配置后再操作。")
      }
      if references.allSatisfy({ state.settings.credentialReferences?[$0.key] == $0.value }) { return state }
      for reference in references.values { removeCredential(reference) }
      throw original
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "BoxmailConfiguration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
