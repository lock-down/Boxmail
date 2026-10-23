import Foundation

public enum AIAPIProtocol: String, Codable, CaseIterable, Identifiable {
  case responses = "openai-responses"
  case chatCompletions = "openai-completions"
  case anthropic = "anthropic-messages"
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .responses: return "OpenAI Responses"
    case .chatCompletions: return "OpenAI Chat Completions"
    case .anthropic: return "Anthropic Messages"
    }
  }
  public var addressPlaceholder: String {
    self == .anthropic ? "https://api.anthropic.com" : "https://gateway.example/v1"
  }
}

public struct AIProvider: Codable, Hashable, Identifiable {
  public var id, name, baseURL, model: String
  public var apiProtocol: AIAPIProtocol
  public var models: [AIModel]
  public var catalogConfigured: Bool?
  public init(id: String, name: String, baseURL: String, apiProtocol: AIAPIProtocol = .chatCompletions,
    model: String = "", models: [AIModel] = []) {
    self.id = id; self.name = name; self.baseURL = baseURL; self.apiProtocol = apiProtocol
    self.model = model; self.models = models
    catalogConfigured = !models.isEmpty
  }
  public var credentialAccount: String { id == "default" ? "ai-key" : "ai-provider-\(id)" }
  public func definition(for modelID: String) -> AIModel {
    resolvedModel(models.first { $0.id == modelID } ?? AIModel(id: modelID))
  }
  public func resolvedModel(_ model: AIModel) -> AIModel {
    var definition = model
    if id == "default", apiProtocol == .responses {
      if definition.input == nil { definition.input = definition.id == "deepseek-v4-pro" ? ["text"] : ["text", "image"] }
      if definition.reasoningEfforts == nil { definition.reasoningEfforts = .mapping(["low": "low", "high": "high", "max": "max"]) }
    }
    return definition
  }
  public static func isValidID(_ id: String) -> Bool {
    id.count <= 64 && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
      && id.range(of: "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
  }
  public var validationIssue: String? {
    if !Self.isValidID(id) { return "服务商 ID 需以小写字母开头，仅使用小写字母、数字和连字符，最多 64 个字符。" }
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 { return "请填写显示名称，最多 80 个字符。" }
    guard let url = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = url.host, !host.isEmpty else { return "请输入有效的 API 地址。" }
    if url.scheme != "https" && !(url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) {
      return "API 地址需使用 HTTPS，本地服务可使用 HTTP。"
    }
    if url.user != nil || url.password != nil || url.query != nil || url.fragment != nil {
      return "API 地址不能包含凭证、查询参数或片段。"
    }
    if models.count > 500 || ([model] + models.map(\.id)).contains(where: {
      $0.count > 500 || $0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }) { return "模型目录最多保留 500 个模型，名称不能含控制字符。" }
    if Set(models.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }).count != models.count { return "同一服务商的模型 ID 不能重复。" }
    if let issue = models.compactMap(\.validationIssue).first { return issue }
    if apiProtocol == .responses, models.contains(where: { $0.maxTokens != nil && $0.maxTokens! < 16 }) {
      return "Responses 的最大输出 token 数至少为 16。"
    }
    return nil
  }
}

public struct AIConfig: Codable, Hashable {
  public var providers: [AIProvider] = [.init(id: "default", name: "DeepSeek", baseURL: "https://api.deepseek.com",
    apiProtocol: .responses, model: "deepseek-flash")]
  public var providerId = "default"
  public var effort = "high"
  public var timeout = 120
  public var enabled = true
  public var prompts: [String: String] = AIPromptDefaults.values
  public init() {}

  public var activeProvider: AIProvider {
    get { providers.first { $0.id == providerId } ?? providers[0] }
    set {
      if let index = providers.firstIndex(where: { $0.id == providerId }) { providers[index] = newValue }
    }
  }
  public var baseURL: String {
    get { activeProvider.baseURL }
    set { activeProvider.baseURL = newValue }
  }
  public var model: String {
    get { activeProvider.model }
    set { activeProvider.model = newValue }
  }
  public var apiProtocol: AIAPIProtocol {
    get { activeProvider.apiProtocol }
    set { activeProvider.apiProtocol = newValue }
  }
  public var credentialAccount: String { activeProvider.credentialAccount }
  public var catalogScope: String { [providerId, apiProtocol.rawValue, baseURL].joined(separator: "|") }
  public var credentialAccounts: [String] { providers.map(\.credentialAccount) }
  public var usesBYOK: Bool { providers.contains { $0.id != "default" || $0.apiProtocol != .responses } }
  public var validationIssue: String? {
    if providers.isEmpty || providers.count > 20 { return "请保留 1 至 20 个 AI 服务商。" }
    if Set(providers.map(\.id)).count != providers.count { return "服务商 ID 已被使用，请更换。" }
    if !providers.contains(where: { $0.id == providerId }) { return "请重新选择当前 AI 服务商。" }
    return providers.compactMap(\.validationIssue).first
  }

  private enum CodingKeys: String, CodingKey {
    case baseURL, model, apiProtocol, providerId, providers, effort, timeout, enabled, prompts
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    effort = try values.decodeIfPresent(String.self, forKey: .effort) ?? "high"
    timeout = try values.decodeIfPresent(Int.self, forKey: .timeout) ?? 120
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    prompts = try values.decodeIfPresent([String: String].self, forKey: .prompts) ?? AIPromptDefaults.values
    if let saved = try values.decodeIfPresent([AIProvider].self, forKey: .providers) {
      providers = saved
      providerId = try values.decodeIfPresent(String.self, forKey: .providerId) ?? "default"
    } else {
      let endpoint = try values.decode(String.self, forKey: .baseURL)
      providers = [.init(id: "default", name: endpoint.contains("deepseek.com") ? "DeepSeek" : "现有连接",
        baseURL: endpoint, apiProtocol: try values.decodeIfPresent(AIAPIProtocol.self, forKey: .apiProtocol) ?? .responses,
        model: try values.decode(String.self, forKey: .model))]
    }
    if let issue = validationIssue {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: issue))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(baseURL, forKey: .baseURL); try values.encode(model, forKey: .model)
    try values.encode(apiProtocol, forKey: .apiProtocol); try values.encode(providerId, forKey: .providerId)
    try values.encode(providers, forKey: .providers); try values.encode(effort, forKey: .effort)
    try values.encode(timeout, forKey: .timeout); try values.encode(enabled, forKey: .enabled)
    try values.encode(prompts, forKey: .prompts)
  }
}
