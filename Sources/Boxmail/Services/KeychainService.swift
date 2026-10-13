import Foundation
import Security

enum KeychainService {
  static let service = "com.boxmail.desktop.credentials"
  static func read(_ account: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return "" }
    guard status == errSecSuccess, let data = result as? Data else { throw credentialError(status) }
    return String(data: data, encoding: .utf8) ?? ""
  }
  static func save(_ value: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if value.isEmpty {
      SecItemDelete(query as CFDictionary)
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
  static func credentialError(_ status: OSStatus) -> NSError {
    NSError(
      domain: "Boxmail", code: Int(status),
      userInfo: [
        NSLocalizedDescriptionKey:
          "无法访问钥匙串：\(SecCopyErrorMessageString(status,nil) as String? ?? String(status))"
      ])
  }
}
