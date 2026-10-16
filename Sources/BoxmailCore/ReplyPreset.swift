import Foundation

public enum ReplyPreset: String, CaseIterable, Identifiable, Codable {
  case interested, decline, thanks
  public var id: String { rawValue }
  public var title: String { Self.definitions[rawValue]!.title }
  public var detail: String { Self.definitions[rawValue]!.detail }
  public var instruction: String { Self.definitions[rawValue]!.instruction }

  private struct Definition: Decodable { let title, detail, instruction: String }
  private static let definitions: [String: Definition] = {
    guard let url = Bundle.module.url(forResource: "ReplyPresets", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let values = try? JSONDecoder().decode([String: Definition].self, from: data),
      allCases.allSatisfy({ values[$0.rawValue] != nil })
    else { preconditionFailure("Boxmail reply presets resource is missing") }
    return values
  }()
}
