import CryptoKit
import Foundation
import OSLog

/// A small, bounded local journal. Callers pass classifications and counters,
/// never request bodies, addresses, credentials, or raw error descriptions.
public final class RuntimeDiagnostics: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.boxmail.diagnostics", qos: .utility)
  private let logger = Logger(subsystem: "com.boxmail.desktop", category: "Runtime")
  private var directory: URL?
  private let maxBytes: Int
  private let copies = 2
  public init(directory: URL?, maxBytes: Int = 1_048_576) {
    self.directory = directory?.appendingPathComponent("logs", isDirectory: true)
    self.maxBytes = maxBytes
  }
  public func setDirectory(_ dataDirectory: URL) {
    queue.async { self.directory = dataDirectory.appendingPathComponent("logs", isDirectory: true) }
  }
  public static func accountReference(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
      .description
  }
  public static func route(_ value: String) -> String {
    let known: Set<String> = [
      "health", "state", "messages", "sync", "sync-status", "cancel", "accounts",
      "test", "settings", "ai", "events", "models", "refresh", "agent", "jobs", "attachments",
      "metadata",
      "download", "search", "rebuild", "configuration", "export", "import", "inspect", "backups",
      "create",
      "restore", "trash", "empty", "drafts", "send", "organizer", "categories", "todos",
      "conversation",
    ]
    return "/"
      + (value.split(separator: "?", maxSplits: 1).first ?? "").split(separator: "/").prefix(6)
      .map { known.contains(String($0)) ? String($0) : ":id" }.joined(separator: "/")
  }
  public static func errorFields(_ error: Error) -> [String: String] {
    let value = error as NSError
    let domains: Set<String> = [
      NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain,
      "Boxmail", "Boxmail.Credentials", "Boxmail.Diagnostics",
    ]
    return [
      "errorType": domains.contains(value.domain) ? value.domain : "Error",
      "code": String(value.code),
    ]
  }
  public func record(_ event: String, _ details: [String: String] = [:]) {
    let allowed: Set<String> = [
      "account", "phase", "status", "method", "route", "code", "errorType",
      "durationMs", "downloaded", "total", "remaining", "attempt", "count", "reason",
    ]
    guard event.range(of: "^[a-z][a-z0-9_.]{1,64}$", options: .regularExpression) != nil else {
      return
    }
    let safe = details.filter { allowed.contains($0.key) && $0.value.utf8.count <= 160 }
    logger.info("\(event, privacy: .public) \(safe.description, privacy: .public)")
    queue.async {
      guard let directory = self.directory else { return }
      do {
        let fm = FileManager.default
        try fm.createDirectory(
          at: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
        else { return }
        let file = directory.appendingPathComponent("app.jsonl")
        if fm.fileExists(atPath: file.path),
          try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        {
          return
        }
        var entry = safe
        entry["event"] = event
        entry["source"] = "app"
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        var line = try JSONSerialization.data(
          withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes])
        line.append(10)
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if size + line.count > self.maxBytes {
          let oldest = file.appendingPathExtension(String(self.copies))
          if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
          for index in stride(from: self.copies - 1, through: 1, by: -1) {
            let from = file.appendingPathExtension(String(index))
            if fm.fileExists(atPath: from.path) {
              try fm.moveItem(at: from, to: file.appendingPathExtension(String(index + 1)))
            }
          }
          if fm.fileExists(atPath: file.path) {
            try fm.moveItem(at: file, to: file.appendingPathExtension("1"))
          }
        }
        if !fm.fileExists(atPath: file.path) {
          fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      } catch { /* Diagnostics must not interrupt mail operations. */  }
    }
  }
  public func flush() async {
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
  }
}
