import Foundation
import Testing
@testable import BoxmailCore

private func configurationFixture() -> ConfigurationArchive {
  var settings = SettingsData()
  settings.preferences.signature = "张三\n示例公司"
  settings.ai.prompts["compose"] = "自定义写信提示词"
  settings.credentialReferences = ["ai-key": "configuration-should-not-export"]
  let account = MailAccount(id: "foreign-account", name: "测试邮箱", email: "test@example.test", username: "test@example.test",
    imapHost: "imap.example.test", smtpHost: "smtp.example.test", lastSync: "private-sync-time")
  return ConfigurationArchive(configuration: .init(accounts: [account], settings: settings),
    credentials: .init(mailPasswords: [account.id: "synthetic-mail-secret"], aiKey: "synthetic-ai-secret"), appVersion: "0.0.14")
}

@Test func configurationArchiveRoundTripsCredentialsAndPreferencesWithoutMachineReferences() throws {
  let value = configurationFixture()
  let bytes = try JSONEncoder().encode(value)
  let restored = try ConfigurationArchive.decode(bytes)
  #expect(restored.credentials.aiKey == "synthetic-ai-secret")
  #expect(restored.credentials.mailPasswords["foreign-account"] == "synthetic-mail-secret")
  #expect(restored.configuration.settings.preferences.signature == "张三\n示例公司")
  #expect(restored.configuration.settings.ai.prompts["compose"] == "自定义写信提示词")
  #expect(restored.configuration.accounts[0].lastSync == nil)
  #expect(restored.configuration.settings.credentialReferences == nil)
  #expect(!String(decoding: bytes, as: UTF8.self).contains("configuration-should-not-export"))
}

@Test func configurationArchiveRejectsUnknownFormatsIncompleteSecretsAndOversizedFiles() throws {
  let original = try JSONEncoder().encode(configurationFixture())
  var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
  for (key, replacement) in [("format", "foreign-document" as Any), ("version", 3 as Any),
    ("credentials", ["mailPasswords": [:], "aiKey": ""] as Any)] {
    var damaged = object; damaged[key] = replacement
    let bytes = try JSONSerialization.data(withJSONObject: damaged)
    #expect(throws: (any Error).self) { try ConfigurationArchive.decode(bytes) }
  }
  object["configuration"] = ["accounts": [], "settings": [:]]
  let incomplete = try JSONSerialization.data(withJSONObject: object)
  #expect(throws: (any Error).self) { try ConfigurationArchive.decode(incomplete) }
  #expect(throws: (any Error).self) { try ConfigurationArchive.decode(Data(repeating: 0x20, count: ConfigurationArchive.maximumBytes + 1)) }
}

@Test func configurationFileUsesPrivatePermissionsAndAtomicReplacement() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("config.json")
  try Data("previous-file".utf8).write(to: file)
  try configurationFixture().write(to: file)
  #expect(try ConfigurationArchive.read(from: file).credentials.aiKey == "synthetic-ai-secret")
  let mode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
  #expect(mode.intValue & 0o777 == 0o600)
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["config.json"])
}
