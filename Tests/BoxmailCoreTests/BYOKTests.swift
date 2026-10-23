import Foundation
import Testing
@testable import BoxmailCore

@Test func legacyAIConfigKeepsItsConnectionPromptsAndCredentialAccount() throws {
  let object: [String: Any] = ["baseURL": "https://custom.example/v1", "model": "my-model",
    "effort": "max", "timeout": 240, "enabled": false, "prompts": ["compose": "使用正式语气"]]
  let config = try JSONDecoder().decode(AIConfig.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(config.providers.count == 1)
  #expect(config.baseURL == "https://custom.example/v1")
  #expect(config.model == "my-model")
  #expect(config.apiProtocol == .responses)
  #expect(config.credentialAccount == "ai-key")
  #expect(config.effort == "max" && config.timeout == 240 && !config.enabled)
  #expect(config.prompts["compose"] == "使用正式语气")
  #expect(config.activeProvider.definition(for: "deepseek-flash").inputTypes == ["text", "image"])
  #expect(config.activeProvider.definition(for: "deepseek-v4-pro").inputTypes == ["text"])
  let override = AIModel(id: "deepseek-flash", input: ["text"], reasoningEfforts: .disabled)
  #expect(config.activeProvider.resolvedModel(override) == override)
}

@Test func providerSwitchingKeepsIndependentSettingsCatalogsAndStableCredentials() throws {
  var config = AIConfig()
  config.providers.append(.init(id: "work-gateway", name: "工作模型", baseURL: "https://gateway.example/v1",
    apiProtocol: .chatCompletions, model: "work-model", models: ["work-model", "other-model"]))
  config.providerId = "work-gateway"
  config.model = "manual-model"
  config.baseURL = "https://gateway.example/custom/v1"
  config.activeProvider.models.removeAll()
  config.activeProvider.catalogConfigured = true
  #expect(config.credentialAccount == "ai-provider-work-gateway")
  #expect(config.providers[0].model == "deepseek-flash")
  let scope = config.catalogScope
  config.apiProtocol = .anthropic
  #expect(scope != config.catalogScope)
  let bytes = try JSONEncoder().encode(config)
  let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  #expect(object["model"] as? String == "manual-model")
  #expect(object["apiProtocol"] as? String == "anthropic-messages")
  let restored = try JSONDecoder().decode(AIConfig.self, from: bytes)
  #expect(restored.activeProvider.models.isEmpty)
  #expect(restored.activeProvider.catalogConfigured == true)
  #expect(restored == config)
  config.providerId = "default"
  #expect(config.model == "deepseek-flash")
  #expect(config.credentialAccount == "ai-key")
}

@Test func customProviderValidationRejectsDuplicateIDsUnsafeURLsAndControlCharacters() throws {
  for id in ["Bad", "1provider", "a--b", "a_b", "a.b", "a-", "custom\n"] { #expect(!AIProvider.isValidID(id)) }
  for id in ["a", "work-gateway", "local1"] { #expect(AIProvider.isValidID(id)) }
  var value = AIProvider(id: "local", name: "本地模型", baseURL: "http://127.0.0.1:1234/v1")
  #expect(value.validationIssue == nil)
  for address in ["http://public.example/v1", "https://user:secret@example.com", "https://example.com?k=secret", "file:///tmp/api"] {
    value.baseURL = address
    #expect(value.validationIssue != nil)
  }
  var config = AIConfig()
  config.providers.append(config.providers[0])
  #expect(config.validationIssue?.contains("ID") == true)
  var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AIConfig())) as? [String: Any])
  object["providers"] = []
  #expect(throws: (any Error).self) { try JSONDecoder().decode(AIConfig.self, from: JSONSerialization.data(withJSONObject: object)) }
}

@Test func configurationV2IncludesAllProviderKeysAndAcceptsLegacyArchives() throws {
  var settings = SettingsData()
  settings.ai.providers.append(.init(id: "work", name: "工作模型", baseURL: "https://gateway.example/v1",
    apiProtocol: .chatCompletions, model: "model", models: ["model"]))
  settings.ai.providerId = "work"
  let archive = ConfigurationArchive(configuration: .init(accounts: [], settings: settings),
    credentials: .init(mailPasswords: [:], aiKey: "legacy-secret", aiProviderKeys: ["work": "work-secret"]), appVersion: "development")
  #expect(archive.version == 2)
  let decoded = try ConfigurationArchive.decode(JSONEncoder().encode(archive))
  #expect(decoded.credentials.aiProviderKeys?["work"] == "work-secret")
  #expect(decoded.configuration.settings.ai.credentialAccount == "ai-provider-work")
  let incomplete = ConfigurationArchive(configuration: archive.configuration,
    credentials: .init(mailPasswords: [:], aiKey: "legacy-secret"), appVersion: "development")
  #expect(throws: (any Error).self) { try incomplete.validated() }
  let legacy = ConfigurationArchive(configuration: .init(accounts: [], settings: .init()),
    credentials: .init(mailPasswords: [:], aiKey: "legacy-secret"), appVersion: "0.0.16")
  #expect(legacy.version == 1)
  var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
  object["credentials"] = ["mailPasswords": [:], "aiKey": "legacy-secret"]
  let restored = try ConfigurationArchive.decode(JSONSerialization.data(withJSONObject: object))
  #expect(restored.credentials.aiKey == "legacy-secret")
  #expect(restored.credentials.aiProviderKeys == nil)
}

@Test func richModelCapabilitiesAndReasoningMappingsRoundTripThroughConfiguration() throws {
  let model = AIModel(id: "work-model", name: "工作模型", contextWindow: 256000, maxTokens: 32000,
    input: ["text", "image"], reasoningEfforts: .mapping(["off": nil, "low": "minimal", "high": "max"]),
    compat: .init(maxTokensField: "max_tokens", forceAdaptiveThinking: true))
  var settings = SettingsData()
  settings.ai.providers.append(.init(id: "work", name: "工作", baseURL: "https://example.com/v1", model: model.id, models: [model]))
  settings.ai.providerId = "work"
  let archive = ConfigurationArchive(configuration: .init(accounts: [], settings: settings),
    credentials: .init(mailPasswords: [:], aiKey: "", aiProviderKeys: ["work": "synthetic-key"]), appVersion: "development")
  let decoded = try ConfigurationArchive.decode(JSONEncoder().encode(archive))
  let restored = try #require(decoded.configuration.settings.ai.activeProvider.models.first)
  #expect(restored == model)
  #expect(restored.reasoningLevels == ["off", "low", "high"])
  #expect(restored.reasoningEfforts?.values?.keys.contains("off") == true)
  #expect(restored.reasoningEfforts?.values?["off"] == .some(nil))
  #expect(restored.inputTypes == ["text", "image"])
}

@Test func modelCapacityParsingUsesDecimalUnitsAndKeepsInvalidDraftsUnsavable() throws {
  for (text, expected) in [("256K", 256000), ("32k", 32000), ("1.5M", 1500000), (" 8192 ", 8192), ("1.024k", 1024)] {
    #expect(AIModel.parseCapacity(text) == expected)
  }
  for text in ["", "0", "-1", "1.5", "NaN", "1e4", "2GB", "999999999999999999999M"] { #expect(AIModel.parseCapacity(text) == nil) }
  var model = AIModel(id: "valid")
  #expect(model.inputTypes == ["text"] && model.reasoningLevels.isEmpty)
  model.maxTokensDraft = "abc"
  #expect(model.validationIssue != nil)
  model.maxTokensDraft = "32K"; model.maxTokens = AIModel.parseCapacity("32K")
  #expect(model.validationIssue == nil)
  let decoded = try JSONDecoder().decode(AIModel.self, from: JSONEncoder().encode(model))
  #expect(decoded.maxTokens == 32000 && decoded.maxTokensDraft == nil)
  model.contextWindow = 16000
  #expect(model.validationIssue?.contains("上下文窗口") == true)
}

@Test func legacyStringCatalogsDecodeAndDuplicateModelsOrInvalidReasoningAreRejected() throws {
  let object: [String: Any] = ["providerId": "custom", "providers": [["id": "custom", "name": "自定义",
    "baseURL": "https://example.com/v1", "apiProtocol": "openai-completions", "model": "model-a", "models": ["model-a", "model-b"]]]]
  var config = try JSONDecoder().decode(AIConfig.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(config.activeProvider.models.map(\.id) == ["model-a", "model-b"])
  #expect(config.activeProvider.definition(for: "model-a").inputTypes == ["text"])
  config.activeProvider.models.append("model-a")
  #expect(config.validationIssue?.contains("重复") == true)
  config.activeProvider.models.removeLast()
  config.activeProvider.models[0].reasoningEfforts = .mapping(["off": nil])
  #expect(config.validationIssue?.contains("非 Off") == true)
  config.activeProvider.models[0].reasoningEfforts = .disabled
  #expect(config.validationIssue == nil)
}
