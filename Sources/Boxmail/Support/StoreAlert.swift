import SwiftUI

extension View {
  func storeAlert(
    _ title: String,
    text: @escaping () -> String?,
    isPresented: @escaping () -> Bool,
    dismiss: @escaping () -> Void
  ) -> some View {
    cossAlert(title, isPresented: Binding(get: isPresented, set: { if !$0 { dismiss() } })) {
      CossAlertAction("确定")
    } message: {
      Text(text() ?? "")
    }
  }
}
