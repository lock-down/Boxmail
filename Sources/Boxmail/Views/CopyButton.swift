import SwiftUI

struct CopyButton: View {
  let help: String
  let action: () -> Void
  @ViewState<Bool> private var copied = false
  @ViewState<Task<Void, Never>?> private var reset: Task<Void, Never>?
  var body: some View {
    IconButton(icon: copied ? "checkmark" : "doc.on.doc", help: copied ? "已复制" : help,
      color: copied ? Palette.success : Palette.muted, active: copied) {
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
