import SwiftUI

struct SettingsActionBar<Leading: View>: View {
  let primaryTitle: String
  var isWorking = false
  var primaryDisabled = false
  var cancelDisabled = false
  let cancel: () -> Void
  let primary: () -> Void
  @ViewBuilder var leading: () -> Leading

  var body: some View {
    HStack(spacing: 12) {
      if isWorking { ProgressView().controlSize(.small) }
      leading()
      Spacer(minLength: 12)
      ActionButton(title: "取消", emphasis: .secondary, size: .form, minimumWidth: 72, action: cancel)
        .keyboardShortcut(.cancelAction).disabled(isWorking || cancelDisabled)
      ActionButton(title: primaryTitle, emphasis: .primary, size: .form, minimumWidth: 72, action: primary)
        .keyboardShortcut(.defaultAction).disabled(isWorking || primaryDisabled)
    }.padding(.horizontal, 24).frame(height: 64).background(Palette.chrome)
      .overlay(alignment: .top) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
  }
}
