import Darwin
import Foundation

/// A local dotenv file, read on every operation so edits also apply to background work.
public struct EnvCredentialStore {
  public let fileURL: URL
  private let references: [String: String]

  public init(fileURL: URL, references: [String: String] = [:]) {
    self.fileURL = fileURL
    self.references = references.filter { key, value in
      (key == "ai-key" || key.hasPrefix("mail-")
        || (key.hasPrefix("ai-provider-") && AIProvider.isValidID(String(key.dropFirst(12)))))
        && value.hasPrefix("configuration-") && UUID(uuidString: String(value.dropFirst(14))) != nil
    }
  }

  public static func fileURL(dataDirectory: URL, override: String? = nil) throws -> URL {
    guard let override else { return dataDirectory.appendingPathComponent(".env") }
    guard override.hasPrefix("/"), !override.contains("\0") else {
      throw failure("BOXMAIL_ENV_FILE 必须是 .env 文件的绝对路径。")
    }
    return URL(fileURLWithPath: override).standardizedFileURL
  }

  public func key(for account: String) throws -> String {
    let account = references[account] ?? account
    let key: String
    if account == "ai-key" { key = "BOXMAIL_AI_KEY" }
    else if account.hasPrefix("ai-provider-") {
      key = "BOXMAIL_AI_PROVIDER_\(account.dropFirst(12))_KEY"
    } else if account.hasPrefix("mail-") {
      key = "BOXMAIL_MAIL_\(account.dropFirst(5))_PASSWORD"
    } else if account.hasPrefix("configuration-") {
      key = "BOXMAIL_CONFIGURATION_\(account.dropFirst(14))"
    } else { throw Self.failure("凭证名称无效。") }
    guard EnvDocument.isValidKey(key) else { throw Self.failure("凭证名称无效。") }
    return key
  }

  public func read(_ account: String) throws -> String {
    let key = try key(for: account)
    return try document().values[key] ?? ""
  }

  public func save(_ value: String, account: String) throws {
    let key = try key(for: account)
    var document = try document()
    try document.set(value, for: key)
    try write(document.text)
  }

  public func createIfNeeded() throws {
    if try existingFile() { return }
    try write("# Boxmail 本机凭证。由设置界面保存，也可直接编辑。\n# 此文件包含明文密钥，请勿提交或分享。\n")
  }

  public static func failure(_ message: String) -> NSError {
    NSError(domain: "Boxmail.Credentials", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func existingFile() throws -> Bool {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw Self.failure("凭证文件必须是普通文件，不能使用目录或符号链接：\(fileURL.path)")
      }
      return true
    } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
      return false
    } catch {
      if (error as NSError).domain == "Boxmail.Credentials" { throw error }
      throw Self.failure("无法读取本机凭证文件，请检查文件权限：\(fileURL.path)")
    }
  }

  private func document() throws -> EnvDocument {
    guard try existingFile() else { return try EnvDocument("") }
    let text: String
    do { text = try String(contentsOf: fileURL, encoding: .utf8) }
    catch { throw Self.failure("无法读取 UTF-8 凭证文件，请检查文件内容和权限：\(fileURL.path)") }
    return try EnvDocument(text)
  }

  private func write(_ text: String) throws {
    let manager = FileManager.default
    let directory = fileURL.deletingLastPathComponent()
    let staging = directory.appendingPathComponent(".boxmail-env-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: staging) }
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      // A sibling temporary file keeps both the write and replacement private and atomic.
      let descriptor = Darwin.open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw Self.failure("无法创建临时凭证文件。") }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      try handle.write(contentsOf: Data(text.utf8))
      try handle.synchronize()
      try handle.close()
      guard Darwin.rename(staging.path, fileURL.path) == 0 else {
        throw Self.failure("无法替换凭证文件。")
      }
    } catch {
      throw Self.failure("无法保存本机凭证，请检查文件夹权限和磁盘空间：\(fileURL.path)")
    }
  }
}

private struct EnvDocument {
  private struct Line {
    var text: String
    let key: String?
  }
  private var lines: [Line] = []
  private(set) var values: [String: String] = [:]
  var text: String { lines.map(\.text).joined(separator: "\n") + "\n" }

  init(_ text: String) throws {
    var text = text.replacingOccurrences(of: "\r\n", with: "\n")
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    var rawLines = text.components(separatedBy: "\n")
    if rawLines.last == "" { rawLines.removeLast() }
    for (index, raw) in rawLines.enumerated() {
      var content = raw.trimmingCharacters(in: .whitespaces)
      if content.isEmpty || content.hasPrefix("#") {
        lines.append(Line(text: raw, key: nil))
        continue
      }
      if content.hasPrefix("export ") || content.hasPrefix("export\t") {
        content = String(content.dropFirst(7)).trimmingCharacters(in: .whitespaces)
      }
      guard let separator = content.firstIndex(of: "=") else { throw Self.invalidLine(index) }
      let key = String(content[..<separator]).trimmingCharacters(in: .whitespaces)
      guard Self.isValidKey(key) else { throw Self.invalidLine(index) }
      let value = String(content[content.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      values[key] = try Self.value(value, line: index)
      lines.append(Line(text: raw, key: key))
    }
  }

  static func isValidKey(_ key: String) -> Bool {
    key.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
  }

  mutating func set(_ value: String, for key: String) throws {
    let position = lines.firstIndex { $0.key == key } ?? lines.count
    lines.removeAll { $0.key == key }
    if !value.isEmpty {
      // JSON strings provide lossless single-line escaping for quotes, slashes and newlines.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes]
      let encoded = String(decoding: try encoder.encode(value), as: UTF8.self)
      lines.insert(Line(text: "\(key)=\(encoded)", key: key), at: min(position, lines.count))
    }
  }

  private static func value(_ raw: String, line: Int) throws -> String {
    guard let quote = raw.first, quote == "\"" || quote == "'" else {
      return String(raw.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
    }
    var escaped = false
    for position in raw.indices.dropFirst() {
      let character = raw[position]
      if escaped { escaped = false; continue }
      if quote == "\"", character == "\\" { escaped = true; continue }
      guard character == quote else { continue }
      let suffix = raw[raw.index(after: position)...].trimmingCharacters(in: .whitespaces)
      guard suffix.isEmpty || suffix.hasPrefix("#") else { throw invalidLine(line) }
      if quote == "'" { return String(raw[raw.index(after: raw.startIndex)..<position]) }
      guard let decoded = try? JSONDecoder().decode(String.self, from: Data(raw[...position].utf8)) else {
        throw invalidLine(line)
      }
      return decoded
    }
    throw invalidLine(line)
  }

  private static func invalidLine(_ index: Int) -> NSError {
    EnvCredentialStore.failure(".env 第 \(index + 1) 行格式无效。请使用 KEY=VALUE，含特殊字符的值用引号包围；双引号内使用 JSON 转义。原文件未作更改。")
  }
}
