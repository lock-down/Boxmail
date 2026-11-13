import CoreFoundation
import Foundation

/// Structural evidence only. Values and arbitrary dictionary keys never enter logs.
enum WireFailureDiagnostic {
  private static let knownFields: Set<String> = {
    guard let url = Bundle.module.url(forResource: "DiagnosticKnownFields", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let words = try? JSONDecoder().decode([String].self, from: data)
    else { preconditionFailure("Boxmail diagnostic field resource is missing") }
    return Set(words)
  }()

  static func fields(_ error: Error, data: Data?) -> [String: String] {
    let context: DecodingError.Context
    var missingKey: CodingKey?
    var fields: [String: String] = ["phase": "decode"]
    switch error {
    case DecodingError.typeMismatch(let type, let detail):
      context = detail
      fields["reason"] = "type_mismatch"
      fields["expectedType"] = expectedType(type)
    case DecodingError.valueNotFound(let type, let detail):
      context = detail
      fields["reason"] = "value_missing"
      fields["expectedType"] = expectedType(type)
    case DecodingError.keyNotFound(let key, let detail):
      context = detail
      missingKey = key
      fields["reason"] = "key_missing"
      fields["expectedType"] = "present"
    case DecodingError.dataCorrupted(let detail):
      context = detail
      fields["reason"] = "invalid_value"
      fields["expectedType"] = "valid_value"
    default: return [:]
    }
    var keys = context.codingPath
    if let missingKey { keys.append(missingKey) }
    let path =
      "$"
      + keys.map { key in
        key.intValue.map { "[\($0)]" } ?? "."
          + (knownFields.contains(key.stringValue) ? key.stringValue : ":key")
      }.joined()
    fields["field"] =
      path.count <= 160 ? path : String(path.prefix(96)) + "..." + String(path.suffix(61))
    let kinds = [
      "messages": "message", "accounts": "account", "attachments": "attachment", "drafts": "draft",
      "jobs": "job", "settings": "settings",
    ]
    fields["recordKind"] = keys.first.flatMap { kinds[$0.stringValue] } ?? "object"
    guard let data else {
      fields["actualType"] = "unavailable"
      return fields
    }
    fields["responseBytes"] = String(data.count)
    guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      fields["actualType"] = "invalid_json"
      return fields
    }
    func remember(_ value: Any?) {
      guard let object = value as? [String: Any] else { return }
      if fields["record"] == nil, let id = object["id"] as? String {
        fields["record"] = RuntimeDiagnostics.accountReference(id)
        if fields["recordKind"] == "account" {
          fields["account"] = RuntimeDiagnostics.accountReference(id)
        }
      }
      if fields["account"] == nil, let id = object["accountId"] as? String {
        fields["account"] = RuntimeDiagnostics.accountReference(id)
      }
    }
    var value: Any? = root
    remember(value)
    for key in keys {
      if let index = key.intValue, let array = value as? [Any] {
        value = array.indices.contains(index) ? array[index] : nil
      } else {
        value = (value as? [String: Any])?[key.stringValue]
      }
      remember(value)
    }
    fields["actualType"] = actualType(value)
    return fields
  }

  private static func expectedType(_ type: Any.Type) -> String {
    if type == String.self { return "string" }
    if type == Bool.self { return "boolean" }
    if type == Int.self || type == Int64.self || type == UInt.self || type == UInt64.self {
      return "integer"
    }
    if type == Double.self || type == Float.self { return "number" }
    if String(describing: type).hasPrefix("Array<") { return "array" }
    return "object"
  }
  private static func actualType(_ value: Any?) -> String {
    guard let value else { return "missing" }
    if value is NSNull { return "null" }
    if value is String { return "string" }
    if let number = value as? NSNumber {
      return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
    }
    if value is [Any] { return "array" }
    return "object"
  }
}
