import Darwin
import Foundation

public struct ConfigurationSnapshot: Codable {
  public var accounts: [MailAccount]
  public var settings: SettingsData
  public init(accounts: [MailAccount], settings: SettingsData) {
    self.accounts = accounts
    self.settings = settings
  }
}

public struct ConfigurationCredentials: Codable {
  public var mailPasswords: [String: String]
  public var aiKey: String
  public var aiProviderKeys: [String: String]?
  public init(mailPasswords: [String: String], aiKey: String, aiProviderKeys: [String: String] = [:]) {
    self.mailPasswords = mailPasswords
    self.aiKey = aiKey
    self.aiProviderKeys = aiProviderKeys
  }
}

public struct ConfigurationArchive: Codable {
  public static let maximumBytes = 2 * 1024 * 1024
  public let format: String
  public let version: Int
  public let createdAt: String
  public let appVersion: String
  public var configuration: ConfigurationSnapshot
  public let credentials: ConfigurationCredentials

  public init(configuration: ConfigurationSnapshot, credentials: ConfigurationCredentials, appVersion: String) {
    format = "boxmail-configuration"
    version = configuration.settings.ai.usesBYOK ? 2 : 1
    createdAt = ISO8601DateFormatter().string(from: Date())
    self.appVersion = appVersion
    self.configuration = configuration
    self.configuration.settings.credentialReferences = nil
    self.configuration.accounts = configuration.accounts.map { value in
      var account = value; account.lastSync = nil; return account
    }
    self.credentials = credentials
  }

  public func validated() throws -> Self {
    guard format == "boxmail-configuration" else { throw failure("请选择 Boxmail 导出的配置 JSON 文件。") }
    guard [1, 2].contains(version), version != 1 || !configuration.settings.ai.usesBYOK else {
      throw failure("此配置文件版本暂不支持，请使用兼容版本的 Boxmail。")
    }
    if let issue = configuration.settings.ai.validationIssue { throw failure(issue) }
    let accounts = configuration.accounts
    guard accounts.count <= 100, accounts.allSatisfy({ !$0.isDemo && !$0.id.isEmpty }),
      Set(accounts.map(\.id)).count == accounts.count,
      Set(credentials.mailPasswords.keys) == Set(accounts.map(\.id)),
      credentials.mailPasswords.values.allSatisfy({ $0.utf8.count <= 16_384 }),
      credentials.aiKey.utf8.count <= 16_384,
      Set((credentials.aiProviderKeys ?? [:]).keys) == Set(configuration.settings.ai.providers.filter { $0.id != "default" }.map(\.id)),
      (credentials.aiProviderKeys ?? [:]).values.allSatisfy({ $0.utf8.count <= 16_384 }) else {
      throw failure("配置文件中的邮箱账号或密钥字段不完整，请重新导出。")
    }
    var result = self
    result.configuration.settings.credentialReferences = nil
    return result
  }

  public static func read(from url: URL) throws -> Self {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
    return try decode(data)
  }

  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else { throw failure("配置文件不能超过 2 MB。") }
    let value: Self
    do { value = try JSONDecoder().decode(Self.self, from: data) }
    catch { throw failure("配置文件格式不完整或已损坏，请重新选择导出的 JSON 文件。") }
    return try value.validated()
  }

  public func write(to url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(validated())
    guard data.count <= Self.maximumBytes else { throw failure("配置内容超过 2 MB，请减少模型目录、账号或自定义提示词后再导出。") }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".Boxmail-Configuration-\(UUID().uuidString).tmp")
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
    try file.write(contentsOf: data)
    try file.synchronize()
    guard rename(temporary.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }
}

private func failure(_ message: String) -> NSError {
  NSError(domain: "BoxmailConfiguration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
