import Foundation

public enum AIPromptDefaults {
  public static let values: [String: String] = {
    guard let url = Bundle.module.url(forResource: "DefaultPrompts", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let prompts = try? JSONDecoder().decode([String: String].self, from: data)
    else { preconditionFailure("Boxmail default prompts resource is missing") }
    return prompts
  }()
}
