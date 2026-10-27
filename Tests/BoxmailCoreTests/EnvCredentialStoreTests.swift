import Foundation
import Testing

@testable import BoxmailCore

private func withEnvStore(_ operation: (EnvCredentialStore) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("boxmail-env-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try operation(EnvCredentialStore(fileURL: directory.appendingPathComponent(".env")))
}

@Test func envCredentialsResolveInsideTheActiveDataDirectoryUnlessExplicitlyOverridden() throws {
  let directory = URL(fileURLWithPath: "/tmp/boxmail-test-data", isDirectory: true)
  #expect(try EnvCredentialStore.fileURL(dataDirectory: directory).path == "/tmp/boxmail-test-data/.env")
  #expect(try EnvCredentialStore.fileURL(dataDirectory: directory, override: "/tmp/custom.env").path == "/tmp/custom.env")
  for invalid in ["", "relative.env", "~/credentials.env", "/tmp/env\0file"] {
    #expect(throws: NSError.self) { try EnvCredentialStore.fileURL(dataDirectory: directory, override: invalid) }
  }
}

@Test func envCredentialsPersistAcrossInstancesAndReadExternalEditsWithoutAuthorization() throws {
  try withEnvStore { store in
    #expect(try store.read("mail-account-a") == "")
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    try store.save("mail-secret", account: "mail-account-a")
    try store.save("provider-secret", account: "ai-provider-custom-api")
    try store.save("default-secret", account: "ai-key")
    let reopened = EnvCredentialStore(fileURL: store.fileURL)
    #expect(try reopened.read("mail-account-a") == "mail-secret")
    #expect(try reopened.read("ai-provider-custom-api") == "provider-secret")
    #expect(try reopened.read("ai-key") == "default-secret")
    try "BOXMAIL_MAIL_account-a_PASSWORD='edited-by-hand'\nBOXMAIL_AI_KEY=new-key\n".write(
      to: store.fileURL, atomically: true, encoding: .utf8)
    #expect(try store.read("mail-account-a") == "edited-by-hand")
    #expect(try reopened.read("ai-key") == "new-key")
    #expect(try store.read("ai-provider-custom-api") == "")
  }
}

@Test func envCredentialsPreserveSpecialCharactersAndNeverExpandShellExpressions() throws {
  try withEnvStore { store in
    let secret = "  密钥 # = \"quoted\" 'single' \\ $HOME ${TOKEN} $(command) `command`\n\r\t  "
    try store.save(secret, account: "ai-key")
    #expect(try store.read("ai-key") == secret)
    #expect(try String(contentsOf: store.fileURL, encoding: .utf8).components(separatedBy: "\n").count == 2)
    try "BOXMAIL_AI_KEY='$HOME ${TOKEN} $(command) `command` # = \\'\n".write(
      to: store.fileURL, atomically: true, encoding: .utf8)
    #expect(try store.read("ai-key") == "$HOME ${TOKEN} $(command) `command` # = \\")
  }
}

@Test func envCredentialUpdatesPreserveCommentsOtherProvidersAndUnknownConfiguration() throws {
  try withEnvStore { store in
    let original = "# keep this comment\nexport UNRELATED = 'left # = right'\n\nBOXMAIL_AI_KEY=old # comment\nBOXMAIL_AI_PROVIDER_custom-api_KEY=provider\nBOXMAIL_AI_KEY=duplicate\n"
    try original.write(to: store.fileURL, atomically: true, encoding: .utf8)
    #expect(try store.read("ai-key") == "duplicate")
    try store.save("new", account: "ai-key")
    let text = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(text.hasPrefix("# keep this comment\nexport UNRELATED = 'left # = right'\n\n"))
    #expect(text.components(separatedBy: "BOXMAIL_AI_KEY=").count == 2)
    #expect(try store.read("ai-provider-custom-api") == "provider")
    try store.save("", account: "ai-key")
    #expect(try store.read("ai-key") == "")
    #expect(try store.read("ai-provider-custom-api") == "provider")
    #expect(try !String(contentsOf: store.fileURL, encoding: .utf8).contains("BOXMAIL_AI_KEY="))
  }
}

@Test func envCredentialsHandleBOMWindowsLineEndingsCommentsAndQuotedValues() throws {
  try withEnvStore { store in
    let input = "\u{FEFF}# comment\r\nexport\tBOXMAIL_AI_KEY = \"abc\\\"#=\\nvalue\" # trailing\r\nBOXMAIL_MAIL_a_PASSWORD= plain=secret # trailing\r\n"
    try input.write(to: store.fileURL, atomically: true, encoding: .utf8)
    #expect(try store.read("ai-key") == "abc\"#=\nvalue")
    #expect(try store.read("mail-a") == "plain=secret")
  }
}

@Test func envCredentialWritesArePrivateAndLeaveNoTemporaryFiles() throws {
  try withEnvStore { store in
    try store.createIfNeeded()
    try store.save("before", account: "ai-key")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
    try store.save("after", account: "ai-key")
    let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let contents = try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
    #expect(contents == [".env"])
    try store.createIfNeeded()
    #expect(try store.read("ai-key") == "after")
  }
}

@Test func malformedEnvCredentialsFailWithoutLeakingSecretsOrOverwritingTheFile() throws {
  try withEnvStore { store in
    for malformed in ["BOXMAIL_AI_KEY='private-secret", "BOXMAIL_AI_KEY=\"private-secret\" extra",
      "BOXMAIL_AI_KEY=\"private-secret\\q\"", "invalid entry private-secret"] {
      try malformed.write(to: store.fileURL, atomically: true, encoding: .utf8)
      do { try store.save("replacement", account: "ai-key"); Issue.record("Malformed dotenv was accepted") }
      catch {
        #expect(error.localizedDescription.contains("第 1 行"))
        #expect(!error.localizedDescription.contains("private-secret"))
      }
      #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == malformed)
    }
  }
}

@Test func envCredentialsRejectSymlinksAndDirectoriesWithoutModifyingTargets() throws {
  try withEnvStore { store in
    let target = store.fileURL.deletingLastPathComponent().appendingPathComponent("other.env")
    try "unrelated-secret".write(to: target, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: target)
    #expect(throws: NSError.self) { try store.read("ai-key") }
    #expect(throws: NSError.self) { try store.save("replacement", account: "ai-key") }
    #expect(try String(contentsOf: target, encoding: .utf8) == "unrelated-secret")
    try FileManager.default.removeItem(at: store.fileURL)
    try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
    #expect(throws: NSError.self) { try store.save("replacement", account: "ai-key") }
  }
}

@Test func envCredentialsKeepAccountAndProviderNamesDistinct() throws {
  try withEnvStore { store in
    for account in ["mail-a-b", "mail-a_b", "mail-A-b", "ai-provider-a-b", "ai-provider-a_b"] {
      try store.save(account, account: account)
    }
    for account in ["mail-a-b", "mail-a_b", "mail-A-b", "ai-provider-a-b", "ai-provider-a_b"] {
      #expect(try store.read(account) == account)
    }
    #expect(throws: NSError.self) { try store.save("value", account: "mail-id\nOTHER") }
  }
}

@Test func envCredentialReferencesPreserveImportRollbackAndExistingSecrets() throws {
  try withEnvStore { store in
    let reference = "configuration-\(UUID())"
    try store.save("original", account: "mail-a")
    try store.save("imported", account: reference)
    let imported = EnvCredentialStore(fileURL: store.fileURL, references: ["mail-a": reference])
    #expect(try imported.read("mail-a") == "imported")
    #expect(try store.read("mail-a") == "original")
    try imported.save("edited", account: "mail-a")
    #expect(try store.read(reference) == "edited")
    try store.save("", account: reference)
    #expect(try store.read("mail-a") == "original")
    #expect(try imported.read("mail-a") == "")
    let invalid = EnvCredentialStore(fileURL: store.fileURL, references: ["mail-a": "configuration-invalid"])
    #expect(try invalid.read("mail-a") == "original")
  }
}
