import AppKit
import BoxmailCore
import SwiftUI

@main struct BoxmailApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @ViewState<MailStore> private var store = MailStore()
  @FocusedValue(\.mailTriage) private var triage: MailStore?
  var body: some Scene {
    WindowGroup("Boxmail", id: "main") {
      ContentView(store: store).frame(minWidth: 1150, minHeight: 720).preferredColorScheme(.light)
        .task {
          delegate.store = store
          if !store.ready { await store.load() }
        }
    }
    .defaultSize(width: 1440, height: 900)
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
      CommandMenu("AI") {
        Button("总结当前邮件") { openAI(.summary) }
          .keyboardShortcut("s", modifiers: [.command, .shift])
          .disabled(store.selectedMailForCommands == nil)
        Button("翻译当前邮件") { openAI(.translate) }
          .keyboardShortcut("t", modifiers: [.command, .shift])
          .disabled(store.selectedMailForCommands == nil)
        Button("理解当前邮件附件") { openAI(.attachment) }
          .disabled(store.selectedMailForCommands?.attachmentIds.isEmpty != false)
        Button("AI 回复当前邮件") { openAI(.reply) }.disabled(store.selectedMailForCommands == nil)
        Divider()
        Button("智能整理收件箱") { store.navigate(.organize) }
      }
    }
    Settings { SettingsView(store: store).preferredColorScheme(.light).borderlessScrollers() }
  }
  private func openAI(_ tab: BoxmailCore.MailAITab) {
    guard let message = store.selectedMailForCommands else { return }
    store.openMail(message)
    store.showMailAI(tab, message: message)
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var store: MailStore?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      KeychainService.clearSession()
    }
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
