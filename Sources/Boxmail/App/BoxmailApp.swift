import AppKit
import BoxmailCore
import SwiftUI

@main struct BoxmailApp: App {
  private static let mainWindowID = "main"
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @FocusedValue(\.mailTriage) private var triage: MailStore?
  @Environment(\.openWindow) private var openWindow
  private var store: MailStore { delegate.store }

  var body: some Scene {
    WindowGroup("Boxmail", id: Self.mainWindowID, for: String.self) { _ in
      ContentView(store: store).frame(
        minWidth: MainWindowLayout.minimumSize.width, minHeight: MainWindowLayout.minimumSize.height
      ).preferredColorScheme(.light)
        .onAppear {
          delegate.openMainWindow = { [openWindow] in
            openWindow(id: Self.mainWindowID, value: Self.mainWindowID)
          }
        }
    } defaultValue: {
      Self.mainWindowID
    }
    .defaultSize(width: MainWindowLayout.defaultSize.width, height: MainWindowLayout.defaultSize.height)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button(store.composer == nil ? "写邮件" : "返回写信") {
          if store.composer == nil { delegate.revealMainWindow() }
          store.newDraft()
        }.keyboardShortcut("n")
          .disabled(!store.ready || (store.composer == nil && (store.showSettings || store.previewAttachment != nil)))
      }
      CommandGroup(replacing: .appSettings) {
        Button("设置…") {
          delegate.revealMainWindow()
          store.showSettings = true
        }.keyboardShortcut(",")
      }
      CommandMenu("邮件") {
        Button("搜索邮件") { store.searchFocusRequest += 1 }.keyboardShortcut("f")
          .disabled(!store.ready || store.showSettings || store.composer != nil || store.previewAttachment != nil)
        Button("同步邮箱") { Task { await store.syncAll() } }.keyboardShortcut(
          "r", modifiers: [.command, .shift])
        Button("回复") { if let m = store.selectedMailForCommands { store.newDraft(reply: m) } }
          .keyboardShortcut("r").disabled(store.selectedMailForCommands == nil)
        Button("转发") {
          if let m = store.selectedMailForCommands { store.newDraft(reply: m, forward: true) }
        }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(store.selectedMailForCommands == nil)
        Button(store.selectedMailForCommands.map { store.isShowingTranslation($0) } == true ? "显示原文" : "翻译邮件") {
          if let message = store.selectedMailForCommands { store.toggleTranslation(message) }
        }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(store.selectedMailForCommands == nil)
        Divider()
        Button("归档邮件") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails.filter { $0.folder != "trash" }, changes: ["folder": "archive"])
        }.keyboardShortcut("a", modifiers: [.control, .command])
          .disabled(triage == nil || triage?.mailActionInProgress == true
            || triage?.selectedMails.contains(where: { $0.folder != "archive" && $0.folder != "trash" }) != true)
        Button("删除邮件") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
        }.keyboardShortcut(.delete, modifiers: [])
          .disabled(triage == nil || triage?.mailActionInProgress == true
            || triage?.selectedMails.contains(where: { $0.folder != "trash" }) != true)
        Button("切换已读") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails, changes: ["unread": !triage.selectedMails.contains(where: \.unread)])
        }.keyboardShortcut("u", modifiers: [.command, .shift])
          .disabled(triage == nil || triage?.mailActionInProgress == true || triage?.selectedMails.isEmpty != false)
      }
    }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = MailStore()
  var openMainWindow: (() -> Void)?

  func applicationWillFinishLaunching(_ notification: Notification) {
    store.notifications.install(store: store) { [weak self] in self?.revealMainWindow() }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let iconFile = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
      let url = Bundle.main.url(forResource: iconFile, withExtension: nil),
      let icon = NSImage(contentsOf: url)
    {
      NSApp.applicationIconImage = icon
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    Task { await store.load() }
  }
  func revealMainWindow() {
    openMainWindow?()
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    guard !hasVisibleWindows, openMainWindow != nil else { return true }
    revealMainWindow()
    return false
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task { @MainActor in
      guard await store.composerWindow.closeForTermination() else {
        sender.reply(toApplicationShouldTerminate: false)
        return
      }
      await store.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
