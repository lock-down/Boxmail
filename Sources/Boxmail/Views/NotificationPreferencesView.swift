import AppKit
import BoxmailCore
import SwiftUI

struct NotificationPreferencesView: View {
  @Binding var preferences: Preferences
  @Bindable var coordinator: NotificationCoordinator
  var body: some View {
    SectionCard(title: "通知与角标", icon: .bell, contentSpacing: 8, inset: 16) {
      WrappingFlowLayout(spacing: 14) {
        preference("来信通知", keyPath: \.newMailNotifications, requiresPermission: true)
        preference("到期提醒", keyPath: \.followUpNotifications, requiresPermission: true)
        preference("显示角标", keyPath: \.badgeEnabled)
          .cossTooltip("角标显示未读邮件与到期跟进数")
        ActionButton(title: "系统通知", icon: .arrowUpRight, size: .compact,
          help: "打开系统通知设置，\(coordinator.permission)") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
          }
        }
      }
      Text(coordinator.permission).font(UIType.small).foregroundStyle(Palette.muted)
      if let error = coordinator.error { WorkflowNotice(text: error, color: Palette.amber) }
    }
  }
  private func preference(_ title: String, keyPath: WritableKeyPath<Preferences, Bool?>,
    requiresPermission: Bool = false) -> some View {
    Toggle(title, isOn: Binding(get: {
      preferences[keyPath: keyPath] ?? (keyPath == \.newMailNotifications && preferences.notifications)
    }, set: { enabled in
      preferences[keyPath: keyPath] = enabled
      if enabled && requiresPermission { Task { _ = await coordinator.requestPermission() } }
    })).toggleStyle(CossToggleStyle()).font(UIType.body).frame(height: UIControlSize.compact.height)
  }
}
