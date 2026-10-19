import Foundation
import Testing

@testable import BoxmailCore

@Test func previewPreservesOriginalBytesAndExtensionWithPrivatePermissions() throws {
  let original = Data([0x50, 0x4b, 0x03, 0x04, 0, 1, 255])
  let file = try AttachmentPreviewFile(name: "../../原始报告.docx", data: original)
  defer { file.remove() }
  #expect(file.url.lastPathComponent == "原始报告.docx")
  #expect(file.url.deletingLastPathComponent() == file.directory)
  #expect(try Data(contentsOf: file.url) == original)
  let permissions =
    try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
  #expect(permissions == 0o600)
}

@Test func previewSessionsDoNotCollideAndCleanupOnlyTheirOwnFiles() throws {
  let a = try AttachmentPreviewFile(name: "report.xlsx", data: Data("first".utf8))
  let b = try AttachmentPreviewFile(name: "C:\\attachments\\report.xlsx", data: Data("second".utf8))
  defer {
    a.remove()
    b.remove()
  }
  #expect(a.url != b.url)
  #expect(b.url.lastPathComponent == "report.xlsx")
  a.remove()
  #expect(!FileManager.default.fileExists(atPath: a.directory.path))
  #expect(try Data(contentsOf: b.url) == Data("second".utf8))
}
