import Foundation
import Testing

@testable import BoxmailCore

@Test func fatalRuntimeClassificationHandlesSplitOutputWithoutReturningPrivateText() {
  let classifier = RuntimeFailureClassifier()
  #expect(
    classifier.consume(
      Data("private-account@example.test FATAL ERROR: JavaScript heap out of mem".utf8))
      == "fatal_abort")
  #expect(classifier.consume(Data("ory private-document-body SECRET\n".utf8)) == "memory_limit")
  #expect(classifier.consume(Data("heap out of memory SECRET".utf8)) == nil)
  let assertion = RuntimeFailureClassifier()
  #expect(assertion.consume(Data("Assertion failed: private-filename".utf8)) == "native_assertion")
}

private final class FatalEvents: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  func append(_ value: String) { lock.withLock { items.append(value) } }
  var values: [String] { lock.withLock { items } }
}

@Test @MainActor func ownedBackendDrainsAndClassifiesFatalStderrBeforeReleasingItsLease()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoxmailFatal-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let events = FatalEvents()
  let backend = try LocalBackendProcess(
    executable: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "printf 'FATAL ERROR: heap out of memory SECRET\\n' >&2; exit 7"],
    directory: root, environment: [:], lease: DataDirectoryLease(directory: root),
    onDiagnostic: { events.append($0) })
  for _ in 0..<100 where backend.isRunning { try await Task.sleep(for: .milliseconds(5)) }
  await backend.stop()
  #expect(events.values == ["memory_limit"])
  #expect(!backend.isRunning)
  _ = try DataDirectoryLease(directory: root)
}
