import AppKit
import SwiftUI

extension NSPasteboard {
  func copy(_ text: String) {
    clearContents()
    setString(text, forType: .string)
  }
}

struct CopyButton: View {
  let help: String
  let action: () -> Void
  @ViewState<Bool> private var copied = false
  @ViewState<Task<Void, Never>?> private var reset: Task<Void, Never>?
  init(help: String, action: @escaping () -> Void) {
    self.help = help
    self.action = action
  }
  init(help: String, text: @escaping () -> String) {
    self.init(help: help) { NSPasteboard.general.copy(text()) }
  }
  var body: some View {
    IconButton(icon: copied ? "checkmark" : "doc.on.doc", help: copied ? "已复制" : help,
      color: copied ? Palette.success : Palette.muted) {
      action()
      copied = true
      reset?.cancel()
      reset = Task {
        do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
        copied = false
      }
    }.onDisappear {
      reset?.cancel()
      copied = false
    }
  }
}
