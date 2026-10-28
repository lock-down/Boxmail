import Foundation

/// Classifies a bounded private stderr window; raw output never leaves this type.
public final class RuntimeFailureClassifier: @unchecked Sendable {
  private let lock = NSLock()
  private var tail = ""
  private var reported: Set<String> = []
  public init() {}
  public func consume(_ data: Data) -> String? {
    lock.withLock {
      tail = String((tail + String(decoding: data, as: UTF8.self)).suffix(16_384))
      let value = tail.lowercased()
      let reason: String?
      if value.contains("heap out of memory") || value.contains("allocation failed")
        || value.contains("std::bad_alloc")
      {
        reason = "memory_limit"
      } else if value.contains("assertion failed") || value.contains("check failed")
        || value.contains("fatal runtime error")
      {
        reason = "native_assertion"
      } else if value.contains("uncaught") || value.contains("unhandledpromiserejection") {
        reason = "unhandled_exception"
      } else if value.contains("fatal error") || value.contains("sigabrt") {
        reason = "fatal_abort"
      } else {
        reason = nil
      }
      guard let reason, reported.insert(reason).inserted else { return nil }
      return reason
    }
  }
}
