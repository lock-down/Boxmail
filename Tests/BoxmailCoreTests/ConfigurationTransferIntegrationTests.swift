import Darwin
import Foundation
import Testing
@testable import BoxmailCore

@MainActor private final class ConfigurationBackend {
  let directory: URL
  private let process = Process()
  private var port = 0
  private let token = "configuration-integration-" + UUID().uuidString

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("boxmail-config-wire-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func start() async throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = directory.appendingPathComponent("startup.log")
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", source.appendingPathComponent("Backend/src/server.js").path]
    process.environment = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/bin:/bin",
      "BOXMAIL_DATA": directory.path, "BOXMAIL_TOKEN": token, "BOXMAIL_PORT": "0", "BOXMAIL_DEMO": "0"]
    process.standardOutput = handle; process.standardError = FileHandle.nullDevice
    try process.run()
    for _ in 0..<200 {
      if let bytes = try? Data(contentsOf: output), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Int],
        let port = value["port"] { self.port = port; return }
      if !process.isRunning { throw failure("Local configuration backend failed to start") }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure("Local configuration backend startup timed out")
  }
  func stop() async {
    if process.isRunning {
      process.terminate()
      for _ in 0..<100 {
        if !process.isRunning { break }
        try? await Task.sleep(for: .milliseconds(20))
      }
      if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
    }
    try? FileManager.default.removeItem(at: directory)
  }
  func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.timeoutInterval = 5
    request.setValue(token, forHTTPHeaderField: "X-Boxmail-Token")
    if let body {
      request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw failure("Configuration request rejected")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func snapshot() async throws -> ConfigurationSnapshot {
    let value: AppSnapshot = try await request("/state?compact=1")
    return .init(accounts: value.accounts, settings: value.settings)
  }
  private func failure(_ message: String) -> NSError { NSError(domain: "ConfigurationIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private struct ConfigurationReceipt: Decodable {}
private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
}

@MainActor @Test func configurationArchiveRoundTripsAcrossSwiftFilesAndRealBackendWithRollbackAndLegacyImport() async throws {
  let source = try ConfigurationBackend(), destination = try ConfigurationBackend()
  do {
    try await source.start(); try await destination.start()
    try await exerciseConfigurationTransfer(source: source, destination: destination)
    await source.stop(); await destination.stop()
  } catch {
    await source.stop(); await destination.stop(); throw error
  }
}

@MainActor @Test func emptyImportedCredentialsAtChangedEndpointsCannotReadTheMachinesExistingSecrets() async throws {
  let backend = try ConfigurationBackend()
  do {
    try await backend.start()
    let account = MailAccount(id: "local", name: "本机邮箱", email: "reader@example.test", username: "reader@example.test",
      imapHost: "imap.trusted.example", smtpHost: "smtp.trusted.example")
    let _: ConfigurationReceipt = try await backend.request("/accounts", body: ["account": object(account)])
    let before = try await backend.snapshot()
    let vault = EnvCredentialStore(fileURL: backend.directory.appendingPathComponent(".env"))
    try vault.save("synthetic-local-ai-secret", account: "ai-key")
    try vault.save("synthetic-local-mail-secret", account: "mail-local")
    var changed = before
    changed.accounts[0].id = "foreign"
    changed.accounts[0].imapHost = "imap.attacker.example"
    changed.accounts[0].smtpHost = "smtp.attacker.example"
    changed.settings.ai.baseURL = "https://attacker.example/v1"
    let archive = ConfigurationArchive(configuration: changed,
      credentials: .init(mailPasswords: ["foreign": ""], aiKey: ""), appVersion: "test")
    let plan: ConfigurationImportPlan = try await backend.request("/configuration/inspect", body: ["configuration": object(changed)])
    #expect(Set(plan.credentialsRequired ?? []) == ["ai-key", "mail-local"])
    let applied = try await ConfigurationTransfer.apply(archive: archive, plan: plan,
      saveCredential: { try vault.save($1, account: $0) }, removeCredential: { try? vault.save("", account: $0) },
      commit: { references in
        #expect(references.isEmpty)
        return try await backend.request("/configuration/import", body: ["configuration": object(archive.configuration),
          "accounts": plan.accounts.map { ["sourceId": $0.sourceId, "accountId": $0.accountId] },
          "revision": plan.revision, "approved": true, "credentialReferences": references])
      }, current: { try await backend.snapshot() })
    #expect(Set(applied.credentialsRequired ?? []) == ["ai-key", "mail-local"])
    let imported = EnvCredentialStore(fileURL: vault.fileURL, references: applied.settings.credentialReferences ?? [:])
    #expect(try imported.read("ai-key").isEmpty)
    #expect(try imported.read("mail-local").isEmpty)
    #expect(try vault.read("ai-key") == "synthetic-local-ai-secret")
    #expect(try vault.read("mail-local") == "synthetic-local-mail-secret")
    await backend.stop()
  } catch { await backend.stop(); throw error }
}

@MainActor private func exerciseConfigurationTransfer(source: ConfigurationBackend, destination: ConfigurationBackend) async throws {
  var settings = SettingsData()
  settings.ai.providers[0].models = [.init(id: "deepseek-flash", name: "默认视觉模型", contextWindow: 256000, maxTokens: 32000,
    input: ["text", "image"], reasoningEfforts: .mapping(["off": nil, "low": "low", "high": "high"]))]
  settings.ai.providers += [
    .init(id: "gateway", name: "工作网关", baseURL: "https://gateway.example/v1", model: "custom-model",
      models: [.init(id: "custom-model", name: "工作模型", contextWindow: 128000, maxTokens: 24000, input: ["text"],
        reasoningEfforts: .disabled, compat: .init(maxTokensField: "max_tokens"))]),
    .init(id: "claude", name: "视觉分析", baseURL: "https://api.anthropic.com", apiProtocol: .anthropic, model: "vision-model",
      models: [.init(id: "vision-model", name: "分析模型", contextWindow: 200000, maxTokens: 32000, input: ["text", "image"],
        reasoningEfforts: .mapping(["off": nil, "high": "max"]), compat: .init(forceAdaptiveThinking: true))]),
  ]
  settings.ai.providerId = "claude"; settings.ai.timeout = 173; settings.ai.enabled = false
  settings.ai.prompts["compose"] = "保留这段自定义提示词"
  settings.preferences.signature = "测试签名\n示例公司"
  let account = MailAccount(id: "source-account", name: "来源邮箱", email: "me@example.test", username: "me@example.test",
    imapHost: "imap.example.test", smtpHost: "smtp.example.test")
  var target = account; target.id = "target-account"; target.email = "ME@example.test"
  var unrelated = account; unrelated.id = "other-account"; unrelated.email = "other@example.test"
  let _: ConfigurationReceipt = try await source.request("/accounts", body: ["account": object(account)])
  let _: ConfigurationReceipt = try await destination.request("/accounts", body: ["account": object(target)])
  let _: ConfigurationReceipt = try await destination.request("/accounts", body: ["account": object(unrelated)])
  let _: SettingsData = try await source.request("/settings", body: ["ai": object(settings.ai), "preferences": object(settings.preferences)])
  let sourceVault = ["ai-key": "wire-default-sentinel", "ai-provider-gateway": "wire-gateway-sentinel",
    "ai-provider-claude": "wire-claude-sentinel", "mail-source-account": "wire-mail-sentinel"]
  let exported: ConfigurationSnapshot = try await source.request("/configuration/export", body: [:])
  let archive = try ConfigurationTransfer.export(snapshot: exported, appVersion: "development") { sourceVault[$0] ?? "" }
  let path = source.directory.appendingPathComponent("configuration.json")
  try archive.write(to: path)
  let decoded = try ConfigurationArchive.read(from: path)
  #expect(decoded.version == 2)
  #expect(decoded.configuration.settings.ai == exported.settings.ai)
  #expect(decoded.configuration.settings.preferences == settings.preferences)

  var vault = ["mail-other-account": "unrelated-mail-sentinel"]
  let original = vault
  let stale: ConfigurationImportPlan = try await destination.request("/configuration/inspect", body: ["configuration": object(decoded.configuration)])
  #expect(stale.accounts.first?.accountId == "target-account")
  let _: SettingsData = try await destination.request("/settings", body: ["preferences": ["signature": "concurrent-edit"]])
  do {
    _ = try await apply(decoded, plan: stale)
    Issue.record("Stale configuration preview unexpectedly applied")
  } catch { #expect(vault == original) }
  let unchanged = try await destination.snapshot()
  #expect(unchanged.settings.preferences.signature == "concurrent-edit")

  let plan: ConfigurationImportPlan = try await destination.request("/configuration/inspect", body: ["configuration": object(decoded.configuration)])
  let applied = try await apply(decoded, plan: plan)
  #expect(applied.accounts.count == 2)
  #expect(applied.settings.ai == decoded.configuration.settings.ai)
  #expect(applied.settings.preferences == decoded.configuration.settings.preferences)
  #expect(vault["mail-other-account"] == "unrelated-mail-sentinel")
  let reexported: ConfigurationSnapshot = try await destination.request("/configuration/export", body: [:])
  let restored = try ConfigurationTransfer.export(snapshot: reexported, appVersion: "development") { logical in
    vault[applied.settings.credentialReferences?[logical] ?? logical] ?? ""
  }
  #expect(restored.credentials.aiKey == decoded.credentials.aiKey)
  #expect(restored.credentials.aiProviderKeys == decoded.credentials.aiProviderKeys)
  #expect(restored.credentials.mailPasswords["target-account"] == decoded.credentials.mailPasswords["source-account"])
  #expect(restored.configuration.settings.credentialReferences == nil)

  // A custom-only file must neither read nor overwrite an unconfigured default key.
  settings.ai.providers.removeAll { $0.id == "default" }
  let _: SettingsData = try await source.request("/settings", body: ["ai": object(settings.ai)])
  let customSnapshot: ConfigurationSnapshot = try await source.request("/configuration/export", body: [:])
  var requested: [String] = []
  let custom = try ConfigurationTransfer.export(snapshot: customSnapshot, appVersion: "development") {
    requested.append($0); return sourceVault[$0] ?? ""
  }
  #expect(!requested.contains("ai-key") && custom.credentials.aiKey.isEmpty)
  let customPlan: ConfigurationImportPlan = try await destination.request("/configuration/inspect", body: ["configuration": object(custom.configuration)])
  let customApplied = try await apply(custom, plan: customPlan)
  #expect(customApplied.settings.credentialReferences?["ai-key"] == applied.settings.credentialReferences?["ai-key"])
  #expect(customApplied.settings.ai.providers.count == 2)
  #expect(customApplied.settings.ai.providers[1].models[0].compat?.forceAdaptiveThinking == true)

  // Import a genuine flat version-1 document into the same destination.
  var legacySettings = SettingsData()
  legacySettings.ai.model = "legacy-model"
  let legacyArchive = ConfigurationArchive(configuration: .init(accounts: [], settings: legacySettings),
    credentials: .init(mailPasswords: [:], aiKey: "wire-legacy-sentinel"), appVersion: "0.0.16")
  var legacy = try object(legacyArchive)
  var configuration = try object(legacyArchive.configuration), oldAI = try object(legacySettings.ai)
  oldAI.removeValue(forKey: "providers"); oldAI.removeValue(forKey: "providerId"); oldAI.removeValue(forKey: "apiProtocol")
  var oldSettings = try object(legacySettings); oldSettings["ai"] = oldAI; configuration["settings"] = oldSettings
  legacy["configuration"] = configuration; legacy["credentials"] = ["mailPasswords": [:], "aiKey": "wire-legacy-sentinel"]
  let legacyDecoded = try ConfigurationArchive.decode(JSONSerialization.data(withJSONObject: legacy))
  let legacyPlan: ConfigurationImportPlan = try await destination.request("/configuration/inspect", body: ["configuration": object(legacyDecoded.configuration)])
  let legacyApplied = try await apply(legacyDecoded, plan: legacyPlan)
  #expect(legacyApplied.settings.ai.providerId == "default" && legacyApplied.settings.ai.model == "legacy-model")
  #expect(legacyApplied.accounts.count == 2)
  #expect(vault[legacyApplied.settings.credentialReferences!["ai-key"]!] == "wire-legacy-sentinel")
  for server in [source, destination] {
    for file in try FileManager.default.contentsOfDirectory(at: server.directory, includingPropertiesForKeys: nil) where file.lastPathComponent.contains(".sqlite") {
      let data = try Data(contentsOf: file)
      for value in Array(sourceVault.values) + ["wire-legacy-sentinel", "unrelated-mail-sentinel"] {
        #expect(data.range(of: Data(value.utf8)) == nil)
      }
    }
  }

  func apply(_ archive: ConfigurationArchive, plan: ConfigurationImportPlan) async throws -> ConfigurationSnapshot {
    try await ConfigurationTransfer.apply(archive: archive, plan: plan, saveCredential: { vault[$0] = $1 },
      removeCredential: { vault.removeValue(forKey: $0) }, commit: { references in
        try await destination.request("/configuration/import", body: ["configuration": object(archive.configuration),
          "accounts": plan.accounts.map { ["sourceId": $0.sourceId, "accountId": $0.accountId] },
          "revision": plan.revision, "approved": true, "credentialReferences": references])
      }, current: { try await destination.snapshot() })
  }
}
