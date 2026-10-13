import AppKit
import SwiftUI

@main struct BoxmailApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @ViewState<MailStore> private var store = MailStore()
  var body: some Scene {
    WindowGroup("Boxmail", id: "main") {
      ContentView(store: store).frame(minWidth: 1150, minHeight: 720).preferredColorScheme(.light)
        .task { if !store.ready { await store.load() } }
    }
    .defaultSize(width: 1440, height: 900)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) { Button("写邮件") { store.newDraft() }.keyboardShortcut("n") }
      CommandGroup(replacing: .appSettings) {
        Button("设置…") { store.showSettings = true }.keyboardShortcut(",")
      }
      CommandMenu("邮件") {
        Button("同步所有账户") { Task { await store.syncAll() } }.keyboardShortcut(
          "r", modifiers: [.command, .shift])
        Button("回复") { if let m = store.selectedMessage { store.newDraft(reply: m) } }
          .keyboardShortcut("r")
        Button("转发") {
          if let m = store.selectedMessage { store.newDraft(reply: m, forward: true) }
        }.keyboardShortcut("f", modifiers: [.command, .shift])
        Button("生成 AI 总结") {
          if let m = store.selectedMessage { store.generate(task: "summary", message: m) }
        }.keyboardShortcut("s", modifiers: [.command, .shift])
      }
    }
    Settings { SettingsView(store: store).preferredColorScheme(.light) }
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated { BackendService.shared.stop() }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
