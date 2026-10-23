import BoxmailCore
import Foundation
import Security

@MainActor enum KeychainService {
  static let service = (Bundle.main.bundleIdentifier ?? "com.boxmail.desktop") + ".credentials"
  private static let session = CredentialSession()
  private static var references: [String: String] = [:]

  static func useReferences(_ values: [String: String]) {
    references = values.filter { key, value in
      (key == "ai-key" || key.hasPrefix("mail-")
        || (key.hasPrefix("ai-provider-") && AIProvider.isValidID(String(key.dropFirst(12))))) && value.hasPrefix("configuration-")
        && UUID(uuidString: String(value.dropFirst(14))) != nil
    }
  }

  static func read(_ account: String, allowInteraction: Bool = true) throws -> String {
    let account = references[account] ?? account
    // File-based Keychain ACL prompts cannot reliably be suppressed by modern LAContext flags.
    // Background work only uses credentials already authorized in this process.
    if !allowInteraction {
      guard let value = session.cachedValue(account) else {
        throw credentialError(errSecInteractionNotAllowed)
      }
      return value
    }
    return try session.read(account) {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account, kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return "" }
      guard status == errSecSuccess, let data = result as? Data else {
        throw credentialError(status)
      }
      return String(data: data, encoding: .utf8) ?? ""
    }
  }

  static func save(_ value: String, account: String) throws {
    let account = references[account] ?? account
    try session.save(value, account: account) {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      if value.isEmpty {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
          throw credentialError(status)
        }
        return
      }
      let update = [kSecValueData as String: Data(value.utf8)]
      let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      if result == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { throw credentialError(status) }
      } else if result != errSecSuccess {
        throw credentialError(result)
      }
    }
  }

  static func clearSession() { session.clear() }
  static func requiresAuthorization(_ error: Error) -> Bool {
    let failure = error as NSError
    return failure.domain == "BoxmailKeychain"
      && [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(
        OSStatus(failure.code))
  }
  private static func credentialError(_ status: OSStatus) -> NSError {
    let message: String
    if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
      message = "需要钥匙串授权。请主动执行操作，在系统提示中输入 Mac 登录密码并选择“始终允许”。"
    } else {
      message = "无法访问钥匙串：\(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
    }
    return NSError(
      domain: "BoxmailKeychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
  }
}
