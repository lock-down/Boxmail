import Darwin
import Foundation

/// A private, byte-for-byte copy owned by one preview session.
public struct AttachmentPreviewFile {
  public let directory: URL
  public let url: URL

  public init(name: String, data: Data, root: URL = FileManager.default.temporaryDirectory) throws {
    let directory = root.appendingPathComponent(
      "BoxmailPreview-\(UUID().uuidString)", isDirectory: true)
    let last = (name.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
    let clean = last.components(separatedBy: .controlCharacters).joined()
    let filename = clean.isEmpty || clean == "." || clean == ".." ? "附件" : clean
    let url = directory.appendingPathComponent(filename)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    do {
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      // Preserve first-open checks when a downloaded attachment is opened externally.
      let quarantine = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Boxmail;"
      quarantine.withCString { value in
        url.path.withCString { path in
          _ = setxattr(path, "com.apple.quarantine", value, strlen(value), 0, 0)
        }
      }
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
    self.directory = directory
    self.url = url
  }

  public func remove() { try? FileManager.default.removeItem(at: directory) }
}
