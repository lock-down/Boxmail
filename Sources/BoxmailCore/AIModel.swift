import Foundation

public enum AIReasoningEfforts: Codable, Hashable {
  case disabled
  case mapping([String: String?])

  public static let levels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
  public var values: [String: String?]? {
    if case .mapping(let values) = self { return values }
    return nil
  }
  public var offeredLevels: [String] { Self.levels.filter { values?.keys.contains($0) == true } }
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if (try? value.decode(Bool.self)) == false { self = .disabled }
    else { self = .mapping(try value.decode([String: String?].self)) }
  }
  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .disabled: try value.encode(false)
    case .mapping(let values): try value.encode(values)
    }
  }
}

public struct AIModelCompatibility: Codable, Hashable {
  public var maxTokensField: String?
  public var forceAdaptiveThinking: Bool?
  public init(maxTokensField: String? = nil, forceAdaptiveThinking: Bool? = nil) {
    self.maxTokensField = maxTokensField; self.forceAdaptiveThinking = forceAdaptiveThinking
  }
}

public struct AIModel: Codable, Hashable, Identifiable, ExpressibleByStringLiteral {
  public var id: String
  public var name: String?
  public var contextWindow: Int?
  public var maxTokens: Int?
  public var input: [String]?
  public var reasoningEfforts: AIReasoningEfforts?
  public var compat: AIModelCompatibility?
  // Unsaved numeric text is retained so invalid input cannot silently turn into an inherited default.
  public var contextWindowDraft: String?
  public var maxTokensDraft: String?

  public init(id: String, name: String? = nil, contextWindow: Int? = nil, maxTokens: Int? = nil,
    input: [String]? = nil, reasoningEfforts: AIReasoningEfforts? = nil, compat: AIModelCompatibility? = nil) {
    self.id = id; self.name = name; self.contextWindow = contextWindow; self.maxTokens = maxTokens
    self.input = input; self.reasoningEfforts = reasoningEfforts; self.compat = compat
  }
  public init(stringLiteral value: String) { self.init(id: value) }
  public var displayName: String { name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : id }
  public var inputTypes: [String] { input ?? ["text"] }
  public var reasoningLevels: [String] { reasoningEfforts?.offeredLevels ?? [] }
  public var validationIssue: String? {
    if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || id.count > 500 || Self.hasControls(id) {
      return "请填写有效的模型 ID，最多 500 个字符。"
    }
    if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 120 || Self.hasControls(name) {
      return "模型显示名称最多 120 个字符，留空时使用模型 ID。"
    }
    for (draft, value) in [(contextWindowDraft, contextWindow), (maxTokensDraft, maxTokens)] {
      if let draft, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Self.parseCapacity(draft) == nil {
        return "容量需为正整数，支持 K、M，例如 256K、32K。"
      }
      if let value, value < 1 || value > 2_147_483_647 { return "容量需为 1 至 2147483647 的正整数。" }
    }
    if let contextWindow, let maxTokens, maxTokens > contextWindow { return "最大输出 token 数不能超过上下文窗口。" }
    if let input, input.isEmpty || input.contains(where: { !["text", "image"].contains($0) }) {
      return "至少选择一种输入类型。"
    }
    if case .mapping(let values) = reasoningEfforts {
      if !values.keys.contains(where: { $0 != "off" }) { return "推理等级至少包含一个非 Off 等级。" }
      for (level, wire) in values {
        if !AIReasoningEfforts.levels.contains(level) { return "推理等级无效。" }
        if let wire {
          if wire.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wire.count > 80 || Self.hasControls(wire) {
            return "请填写有效的推理等级发送值。"
          }
        } else if level != "off" { return "非 Off 推理等级必须填写发送值。" }
      }
    }
    if let field = compat?.maxTokensField, !["max_tokens", "max_completion_tokens"].contains(field) {
      return "输出上限参数无效。"
    }
    return nil
  }
  private static func hasControls(_ value: String) -> Bool { value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
  public static func parseCapacity(_ text: String) -> Int? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard text.range(of: "^([0-9]+(?:\\.[0-9]+)?)([km])?$", options: .regularExpression) != nil else { return nil }
    let multiplier: Double = text.hasSuffix("m") ? 1_000_000 : text.hasSuffix("k") ? 1000 : 1
    let digits = multiplier == 1 ? text : String(text.dropLast())
    guard let number = Double(digits) else { return nil }
    let tokens = number * multiplier, rounded = tokens.rounded()
    guard tokens.isFinite, rounded >= 1, rounded <= 2_147_483_647, abs(tokens - rounded) < 0.000001 else { return nil }
    return Int(rounded)
  }
  public static func formatCapacity(_ value: Int?) -> String {
    guard let value else { return "" }
    if value % 1_000_000 == 0 { return "\(value / 1_000_000)M" }
    if value % 1000 == 0 { return "\(value / 1000)K" }
    return String(value)
  }
  private enum CodingKeys: String, CodingKey { case id, name, contextWindow, maxTokens, input, reasoningEfforts, compat }
  public init(from decoder: Decoder) throws {
    if let id = try? decoder.singleValueContainer().decode(String.self) { self.init(id: id); return }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(id: try values.decode(String.self, forKey: .id))
    name = try values.decodeIfPresent(String.self, forKey: .name)
    contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
    maxTokens = try values.decodeIfPresent(Int.self, forKey: .maxTokens)
    input = try values.decodeIfPresent([String].self, forKey: .input)
    reasoningEfforts = try values.decodeIfPresent(AIReasoningEfforts.self, forKey: .reasoningEfforts)
    compat = try values.decodeIfPresent(AIModelCompatibility.self, forKey: .compat)
  }
}
