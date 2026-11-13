import SwiftUI

extension View {
  func storeAlert(
    _ title: String,
    text: @escaping () -> String?,
    isPresented: @escaping () -> Bool,
    dismiss: @escaping () -> Void
  ) -> some View {
    alert(title, isPresented: Binding(get: isPresented, set: { if !$0 { dismiss() } })) {
      Button("确定") { dismiss() }
    } message: {
      Text(text() ?? "")
    }
  }
}
