import Foundation
import Testing

@testable import BoxmailCore

private enum UpdateFailure: Error { case write, rejected, offline }

@MainActor @Test func rejectedSettingsSaveCannotOverwriteTheLiveCredential() async throws {
  var vault = ["ai-key": "existing-key"]
  var staged: [String: String] = [:]
  do {
    let _: Bool = try await CredentialUpdate.apply(
      values: ["ai-key": "replacement-key"], save: { vault[$0] = $1 },
      remove: { vault.removeValue(forKey: $0) },
      commit: {
        staged = $0
        #expect(vault["ai-key"] == "existing-key")
        throw UpdateFailure.rejected
      }, current: { (false, [:]) })
    Issue.record("Rejected settings must fail")
  } catch { #expect(error is UpdateFailure) }
  #expect(vault["ai-key"] == "existing-key")
  #expect(staged["ai-key"] != "ai-key")
  #expect(vault[staged["ai-key"] ?? ""] == "replacement-key")
}

@MainActor @Test func credentialWriteFailureCannotPublishPartialSettings() async throws {
  var vault = ["mail-account": "existing-password"]
  var writes = 0
  var commits = 0
  do {
    let _: Bool = try await CredentialUpdate.apply(
      values: ["ai-key": "new-key", "mail-account": "new-password"],
      save: {
        writes += 1
        if writes == 2 { throw UpdateFailure.write }
        vault[$0] = $1
      }, remove: { vault.removeValue(forKey: $0) },
      commit: { _ in
        commits += 1
        return true
      }, current: { (false, [:]) })
    Issue.record("A credential write failure must fail the save")
  } catch { #expect(error is UpdateFailure) }
  #expect(commits == 0)
  #expect(vault == ["mail-account": "existing-password"])
}

@MainActor @Test func lostSettingsResponseUsesTheCommittedCredentialReferences() async throws {
  var vault = ["ai-key": "old-key"]
  var published: [String: String] = [:]
  let result = try await CredentialUpdate.apply(
    values: ["ai-key": "new-key"], save: { vault[$0] = $1 },
    remove: { vault.removeValue(forKey: $0) },
    commit: {
      published = $0
      throw UpdateFailure.offline
    }, current: { ("committed", published) })
  #expect(result == "committed")
  #expect(vault[published["ai-key"] ?? ""] == "new-key")
  #expect(vault["ai-key"] == "old-key")
}

@MainActor @Test func unconfirmedSettingsKeepEveryPotentiallyLiveCredential() async throws {
  var vault = ["mail-account": "old-password"]
  var published: [String: String] = [:]
  do {
    let _: Bool = try await CredentialUpdate.apply(
      values: ["mail-account": "new-password"], save: { vault[$0] = $1 },
      remove: { vault.removeValue(forKey: $0) },
      commit: {
        published = $0
        throw UpdateFailure.offline
      }, current: { throw UpdateFailure.offline })
    Issue.record("An unconfirmed save must report uncertainty")
  } catch { #expect(error.localizedDescription.contains("无法确认保存结果")) }
  #expect(vault["mail-account"] == "old-password")
  #expect(vault[published["mail-account"] ?? ""] == "new-password")
}

@MainActor @Test func clearingAnAPIKeyPublishesAnEmptyReferenceWithoutChangingThePreviousKey()
  async throws
{
  var vault = ["ai-key": "old-key"]
  let reference: String = try await CredentialUpdate.apply(
    values: ["ai-key": ""], save: { vault[$0] = $1 },
    remove: { vault.removeValue(forKey: $0) }, commit: { $0["ai-key"]! },
    current: { ("", [:]) })
  #expect(vault[reference] == "")
  #expect(vault["ai-key"] == "old-key")
}
