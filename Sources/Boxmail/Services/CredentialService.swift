import BoxmailCore
import Foundation

@MainActor enum CredentialService {
  private static var references: [String: String] = [:]

  private static func storage() throws -> EnvCredentialStore {
    let url = try EnvCredentialStore.fileURL(dataDirectory: BackendService.shared.dataDirectory,
      override: ProcessInfo.processInfo.environment["BOXMAIL_ENV_FILE"])
    return EnvCredentialStore(fileURL: url, references: references)
  }

  static var fileURL: URL { get throws { try storage().fileURL } }
  static func useReferences(_ values: [String: String]) { references = values }
  static func read(_ account: String) throws -> String { try storage().read(account) }
  static func save(_ value: String, account: String) throws { try storage().save(value, account: account) }
  static func createFileIfNeeded() throws { try storage().createIfNeeded() }

  static func mailPassword(for accountID: String) throws -> String {
    let password = try read("mail-\(accountID)")
    guard !password.isEmpty else {
      throw EnvCredentialStore.failure("本机 .env 未配置此邮箱的授权码，请在“设置 > 账号”重新填写并保存，或导入已导出的配置。")
    }
    return password
  }

  static func isCredentialError(_ error: Error) -> Bool {
    (error as NSError).domain == "Boxmail.Credentials"
  }
}
