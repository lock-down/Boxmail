import Darwin
import Foundation
import Testing

@testable import BoxmailCore

@MainActor private final class ContentBackend {
  let directory: URL
  private var process: Process?
  private var port = 0
  private let token = "synthetic-content-" + UUID().uuidString
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "boxmail-content-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func start() async throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let output = directory.appendingPathComponent(UUID().uuidString + ".json")
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    child.arguments = [
      "node", source.appendingPathComponent("Backend/test/helpers/content-wire.js").path,
      directory.path, token,
    ]
    child.standardOutput = handle
    child.standardError = FileHandle.nullDevice
    try child.run()
    process = child
    for _ in 0..<400 {
      if let bytes = try? Data(contentsOf: output),
        let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Int],
        let port = value["port"]
      {
        self.port = port
        return
      }
      if !child.isRunning { throw URLError(.cannotConnectToHost) }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw URLError(.timedOut)
  }
  func stop() async {
    guard let child = process else { return }
    if child.isRunning { child.terminate() }
    for _ in 0..<200 {
      if !child.isRunning { break }
      try? await Task.sleep(for: .milliseconds(20))
    }
    if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    child.waitUntilExit()
    process = nil
  }
  func remove() { try? FileManager.default.removeItem(at: directory) }
  func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.timeoutInterval = 10
    request.setValue(token, forHTTPHeaderField: "X-Boxmail-Token")
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (bytes, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    return try JSONDecoder().decode(T.self, from: bytes)
  }
}

@MainActor @Test
func twelveThousandMessagesWithLegacyUnicodeKeepStartupBodiesAndSavedSettingsAfterRestart()
  async throws
{
  let backend = try ContentBackend()
  do {
    try await backend.start()
    let snapshot: AppSnapshot = try await backend.request("/state?compact=1&previews=0")
    #expect(snapshot.messages.count == 12001)
    #expect(snapshot.accounts.count == 6)
    let full: MailMessage = try await backend.request("/messages/legacy")
    let originalBody =
      String(repeating: "a", count: 139) + String(UnicodeScalar(0x20bb7)!) + " original body tail"
    #expect(full.body == originalBody)
    #expect(full.subject == "\u{fffd}")
    #expect(full.html == "<p>\(originalBody)</p>")
    let page: MailPage = try await backend.request(
      "/messages?accountId=a0&groupBy=sender&revealId=legacy")
    #expect(page.total == 2001)
    let settings: SettingsData = try await backend.request(
      "/settings", body: ["preferences": ["fontSize": 18]])
    #expect(settings.preferences.fontSize == 18)
    let refreshed: AppSnapshot = try await backend.request("/state?compact=1&previews=0")
    #expect(refreshed.messages.count == 12001 && refreshed.settings.preferences.fontSize == 18)
    await backend.stop()
    try await backend.start()
    let reopened: AppSnapshot = try await backend.request("/state?compact=1&previews=0")
    let restored: MailMessage = try await backend.request("/messages/legacy")
    #expect(reopened.messages.count == 12001 && reopened.settings.preferences.fontSize == 18)
    #expect(restored.body == originalBody && restored.html == full.html)
    await backend.stop()
    backend.remove()
  } catch {
    await backend.stop()
    backend.remove()
    throw error
  }
}
