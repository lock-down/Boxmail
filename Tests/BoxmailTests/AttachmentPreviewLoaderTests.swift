import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

@Test @MainActor func previewPreparationPreservesBytesAndCancellationLeavesNoFiles() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BoxmailPreviewCleanup-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let data = Data(repeating: 65, count: 1024 * 1024)
  let file = try await AttachmentPreviewLoader.prepare(
    name: "资料.txt", content: data.base64EncodedString(), isPDF: false, root: root)
  defer { file.remove() }
  #expect(try Data(contentsOf: file.url) == data)
  file.remove()
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
  let invalid = Task {
    try await AttachmentPreviewLoader.prepare(
      name: "bad.pdf", content: data.base64EncodedString(), isPDF: true, root: root)
  }
  do {
    _ = try await invalid.value
    Issue.record("Invalid PDF was accepted")
  } catch {}
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
  let cancelled = Task {
    try await AttachmentPreviewLoader.prepare(
      name: "cancelled.txt", content: data.base64EncodedString(), isPDF: false, root: root)
  }
  cancelled.cancel()
  do {
    let leaked = try await cancelled.value
    leaked.remove()
    Issue.record("Cancelled preview was accepted")
  } catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
