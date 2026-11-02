import Foundation

/// Publish new credentials through fresh references so a rejected save cannot overwrite live keys.
@MainActor public enum CredentialUpdate {
  public static func apply<Result>(
    values: [String: String],
    save: (String, String) throws -> Void,
    remove: (String) -> Void,
    commit: ([String: String]) async throws -> Result,
    current: () async throws -> (Result, [String: String])
  ) async throws -> Result {
    guard !values.isEmpty else { return try await commit([:]) }
    var references: [String: String] = [:]
    do {
      for logical in values.keys.sorted() {
        let reference = "configuration-\(UUID().uuidString)"
        try save(reference, values[logical]!)
        references[logical] = reference
      }
    } catch {
      for reference in references.values { remove(reference) }
      throw error
    }
    do { return try await commit(references) } catch {
      let failure = error
      let state: (Result, [String: String])
      do { state = try await current() } catch {
        // A response can be lost after SQLite commits. Retain potentially live credentials.
        throw EnvCredentialStore.failure("暂时无法确认保存结果，请重新打开设置检查后再操作。")
      }
      if references.allSatisfy({ state.1[$0.key] == $0.value }) { return state.0 }
      // The original request may still be in flight, so do not delete its staged credentials.
      throw failure
    }
  }
}
