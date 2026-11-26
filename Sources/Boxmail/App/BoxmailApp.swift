import AppKit
import BoxmailCore
import SwiftUI

@main struct BoxmailApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @ViewState<MailStore> private var store = MailStore()
  @FocusedValue(\.mailTriage) private var triage: MailStore?
  var body: some Scene {
    WindowGroup("Boxmail", id: "main") {
      ContentView(store: store).frame(
        minWidth: MainWindowLayout.minimumSize.width, minHeight: MainWindowLayout.minimumSize.height
      ).preferredColorScheme(.light)
        .task {
          delegate.store = store
          if !store.ready { await store.load() }
        }
    }
    .defaultSize(width: MainWindowLayout.defaultSize.width, height: MainWindowLayout.defaultSize.height)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("写邮件") { store.newDraft() }.keyboardShortcut("n")
          .disabled(!store.ready || store.composer != nil || store.showSettings || store.previewAttachment != nil)
      }
      CommandGroup(replacing: .appSettings) {
        Button("设置…") { store.showSettings = true }.keyboardShortcut(",")
      }
      CommandMenu("邮件") {
        Button("搜索邮件") { store.searchFocusRequest += 1 }.keyboardShortcut("f")
          .disabled(!store.ready || store.showSettings || store.composer != nil || store.previewAttachment != nil)
        Button("同步所有账户") { Task { await store.syncAll() } }.keyboardShortcut(
          "r", modifiers: [.command, .shift])
        Button("回复") { if let m = store.selectedMailForCommands { store.newDraft(reply: m) } }
          .keyboardShortcut("r").disabled(store.selectedMailForCommands == nil)
        Button("转发") {
          if let m = store.selectedMailForCommands { store.newDraft(reply: m, forward: true) }
        }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(store.selectedMailForCommands == nil)
        Button(store.selectedMailForCommands.map { store.isShowingTranslation($0) } == true ? "显示原文" : "翻译当前邮件") {
          if let message = store.selectedMailForCommands { store.toggleTranslation(message) }
        }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(store.selectedMailForCommands == nil)
        Divider()
        Button("归档所选邮件") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails.filter { $0.folder != "trash" }, changes: ["folder": "archive"])
        }.keyboardShortcut("a", modifiers: [.control, .command])
          .disabled(triage == nil || triage?.mailActionInProgress == true
            || triage?.selectedMails.contains(where: { $0.folder != "archive" && $0.folder != "trash" }) != true)
        Button("移到已删除") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails.filter { $0.folder != "trash" }, changes: ["folder": "trash"])
        }.keyboardShortcut(.delete, modifiers: [])
          .disabled(triage == nil || triage?.mailActionInProgress == true
            || triage?.selectedMails.contains(where: { $0.folder != "trash" }) != true)
        Button("切换已读状态") {
          guard let triage else { return }
          triage.updateMessages(triage.selectedMails, changes: ["unread": !triage.selectedMails.contains(where: \.unread)])
        }.keyboardShortcut("u", modifiers: [.command, .shift])
          .disabled(triage == nil || triage?.mailActionInProgress == true || triage?.selectedMails.isEmpty != false)
      }
    }
    Settings {
      SettingsView(store: store).preferredColorScheme(.light).borderlessScrollers()
        .workspaceSheet(.settings)
    }
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var store: MailStore?
  func applicationDidFinishLaunching(_ notification: Notification) {
    if let url = Bundle.main.url(forResource: "Boxmail", withExtension: "icns"),
      let icon = NSImage(contentsOf: url)
    {
      NSApp.applicationIconImage = icon
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task { @MainActor in
      if let store { await store.stop() }
      else { await BackendService.shared.stop() }
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
