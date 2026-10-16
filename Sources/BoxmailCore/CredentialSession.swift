import Foundation

/// Keeps successfully authorized credentials in memory for the current app process.
@MainActor public final class CredentialSession {
  private var values: [String: String] = [:]
  public init() {}
  public func cachedValue(_ account: String) -> String? { values[account] }

  public func read(_ account: String, load: () throws -> String) rethrows -> String {
    if let value = values[account] { return value }
    let value = try load()
    values[account] = value
    return value
  }

  public func save(_ value: String, account: String, persist: () throws -> Void) rethrows {
    if values[account] == value { return }
    try persist()
    values[account] = value
  }

  public func clear() { values.removeAll() }
}
