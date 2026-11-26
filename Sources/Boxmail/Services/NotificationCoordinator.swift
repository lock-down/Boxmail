import AppKit
import BoxmailCore
import Observation
import UserNotifications

@Observable @MainActor final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
  private let backend: BackendService
  private weak var store: MailStore?
  var permission = "尚未请求"
  var error: String?
  init(backend: BackendService) { self.backend = backend }
  func requestPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      permission = granted ? "已允许" : "未允许，可在系统设置中开启"
      return granted
    } catch { self.error = error.localizedDescription; return false }
  }
  func poll(store: MailStore) async {
    self.store = store
    let preferences = store.settings.preferences
    if preferences.badgeEnabled == true {
      let count = store.messages.filter { $0.folder == "inbox" && $0.unread }.count
        + (store.lastWorkspaceStatus?.dueFollowUpCount ?? 0)
      NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    } else { NSApp.dockTile.badgeLabel = nil }
    guard preferences.newMailNotifications ?? preferences.notifications || preferences.followUpNotifications == true else { return }
    do {
      let center = UNUserNotificationCenter.current(); center.delegate = self
      let settings = await center.notificationSettings()
      permission = settings.authorizationStatus == .authorized ? "已允许" : "未允许，可在系统设置中开启"
      guard settings.authorizationStatus == .authorized else { return }
      let pending: [LocalNotification] = try await backend.request("/local-notifications")
      for item in pending {
        let content = UNMutableNotificationContent()
        content.title = item.kind == "followUp" ? "清单事项已到期" : "新邮件"
        content.body = item.title; content.sound = .default
        content.userInfo = ["messageId": item.messageId]
        if let id = item.followUpId { content.userInfo["followUpId"] = id }
        try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
        try await backend.perform("/local-notifications/\(item.id)/ack", body: [:])
      }
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let request = response.notification.request
    let messageId = request.content.userInfo["messageId"] as? String
    let followUpId = request.content.userInfo["followUpId"] as? String ?? Self.legacyFollowUpId(request.identifier)
    Task { @MainActor in
      if let followUpId { self.store?.revealChecklistItem(followUpId) }
      else if let messageId { self.store?.openSourceMessage(messageId) }
      NSApp.activate(ignoringOtherApps: true)
      completionHandler()
    }
  }
  private nonisolated static func legacyFollowUpId(_ identifier: String) -> String? {
    let prefix = "followUp-"
    guard identifier.hasPrefix(prefix) else { return nil }
    let remainder = identifier.dropFirst(prefix.count)
    guard let date = remainder.range(of: #"-\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) else { return nil }
    return String(remainder[..<date.lowerBound])
  }
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}
private struct LocalNotification: Decodable {
  let id, kind, title, messageId: String
  let followUpId: String?
}
