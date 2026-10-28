import BoxmailCore
import Foundation

extension MailStore {
  /// A refresh failure must not turn a committed settings save into a false failure.
  func saveSettings(ai: AIConfig, preferences: Preferences) async throws -> Bool {
    let saved: SettingsData = try await backend.request(
      "/settings", method: "POST",
      body: ["ai": try jsonObject(ai), "preferences": try jsonObject(preferences)])
    settings = saved
    CredentialService.useReferences(saved.credentialReferences ?? [:])
    do {
      try await refresh()
      return true
    } catch { return false }
  }
}
