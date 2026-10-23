import Foundation
import Testing
@testable import BoxmailCore

private enum TransferFailure: Error { case write, response, offline }

@MainActor private func transferArchive() -> ConfigurationArchive {
  var settings = SettingsData()
  settings.ai.providers = [
    .init(id: "alpha", name: "Alpha", baseURL: "https://alpha.example/v1", model: "model-a", models: ["model-a"]),
    .init(id: "beta", name: "Beta", baseURL: "https://beta.example", apiProtocol: .anthropic, model: "model-b", models: ["model-b"]),
  ]
  settings.ai.providerId = "alpha"
  return ConfigurationArchive(configuration: .init(accounts: [], settings: settings),
    credentials: .init(mailPasswords: [:], aiKey: "unused-legacy-value", aiProviderKeys: ["alpha": "alpha-secret", "beta": "beta-secret"]),
    appVersion: "development")
}

@MainActor @Test func configurationExportReadsOnlyCredentialsOwnedByConfiguredProviders() throws {
  let snapshot = transferArchive().configuration
  var reads: [String] = []
  let archive = try ConfigurationTransfer.export(snapshot: snapshot, appVersion: "development") { account in
    reads.append(account)
    return "synthetic-" + account
  }
  #expect(Set(reads) == Set(snapshot.settings.ai.credentialAccounts))
  #expect(!reads.contains("ai-key"))
  #expect(archive.credentials.aiKey.isEmpty)
  #expect(archive.version == 2)
  #expect(archive.credentials.aiProviderKeys?["alpha"] == "synthetic-ai-provider-alpha")
  #expect(archive.credentials.aiProviderKeys?["beta"] == "synthetic-ai-provider-beta")
}

@MainActor @Test func configurationExportRejectsInvalidModelDraftsBeforeReadingCredentials() throws {
  var snapshot = transferArchive().configuration
  snapshot.settings.ai.providers[0].models[0].maxTokensDraft = "invalid"
  var reads = 0
  #expect(throws: (any Error).self) {
    try ConfigurationTransfer.export(snapshot: snapshot, appVersion: "development") { _ in reads += 1; return "" }
  }
  #expect(reads == 0)
}

@MainActor @Test func partialCredentialWriteFailureRemovesStagedKeysAndKeepsExistingSecrets() async throws {
  var vault = ["existing-reference": "existing-secret"]
  var writes = 0, commits = 0
  do {
    _ = try await ConfigurationTransfer.apply(archive: transferArchive(), plan: .init(revision: "r", accounts: []),
      saveCredential: { reference, value in
        writes += 1
        if writes == 2 { throw TransferFailure.write }
        vault[reference] = value
      }, removeCredential: { vault.removeValue(forKey: $0) }, commit: { _ in
        commits += 1; return transferArchive().configuration
      }, current: { transferArchive().configuration })
    Issue.record("Credential write failure unexpectedly succeeded")
  } catch { #expect(error is TransferFailure) }
  #expect(writes == 2 && commits == 0)
  #expect(vault == ["existing-reference": "existing-secret"])
}

@MainActor @Test func rejectedImportDiscardsOnlyNewReferences() async throws {
  var vault = ["existing-reference": "existing-secret"]
  do {
    _ = try await ConfigurationTransfer.apply(archive: transferArchive(), plan: .init(revision: "r", accounts: []),
      saveCredential: { vault[$0] = $1 }, removeCredential: { vault.removeValue(forKey: $0) },
      commit: { _ in throw TransferFailure.response }, current: { transferArchive().configuration })
    Issue.record("Rejected import unexpectedly succeeded")
  } catch { #expect(error is TransferFailure) }
  #expect(vault == ["existing-reference": "existing-secret"])
}

@MainActor @Test func committedImportWithLostResponseKeepsItsLiveCredentials() async throws {
  var vault: [String: String] = [:]
  var committed = transferArchive().configuration
  let applied = try await ConfigurationTransfer.apply(archive: transferArchive(), plan: .init(revision: "r", accounts: []),
    saveCredential: { vault[$0] = $1 }, removeCredential: { vault.removeValue(forKey: $0) }, commit: { references in
      committed.settings.credentialReferences = references
      throw TransferFailure.response
    }, current: { committed })
  #expect(vault.count == 2)
  #expect(applied.settings.credentialReferences == committed.settings.credentialReferences)
  #expect(vault[applied.settings.credentialReferences!["ai-provider-alpha"]!] == "alpha-secret")
  #expect(applied.settings.credentialReferences?["ai-key"] == nil)
}

@MainActor @Test func unresolvedImportRetainsPossibleLiveKeysForRecovery() async throws {
  var vault: [String: String] = [:]
  do {
    _ = try await ConfigurationTransfer.apply(archive: transferArchive(), plan: .init(revision: "r", accounts: []),
      saveCredential: { vault[$0] = $1 }, removeCredential: { vault.removeValue(forKey: $0) },
      commit: { _ in throw TransferFailure.response }, current: { throw TransferFailure.offline })
    Issue.record("Unresolved import unexpectedly succeeded")
  } catch { #expect(error.localizedDescription.contains("暂时无法确认")) }
  #expect(Set(vault.values) == Set(["alpha-secret", "beta-secret"]))
}

@MainActor @Test func invalidImportPlanCannotStageCredentials() async throws {
  var writes = 0
  do {
    _ = try await ConfigurationTransfer.apply(archive: transferArchive(), plan: .init(revision: "r", accounts: [
      .init(sourceId: "missing", accountId: "target", name: "", email: "", existing: false),
    ]), saveCredential: { _, _ in writes += 1 }, removeCredential: { _ in },
      commit: { _ in transferArchive().configuration }, current: { transferArchive().configuration })
    Issue.record("Invalid mapping unexpectedly succeeded")
  } catch { #expect(error.localizedDescription.contains("账号映射")) }
  #expect(writes == 0)
}
