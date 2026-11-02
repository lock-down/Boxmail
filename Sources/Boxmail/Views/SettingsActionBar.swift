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
      FooterActionButton(title: "取消", primary: false, action: cancel)
        .keyboardShortcut(.cancelAction).disabled(isWorking || cancelDisabled)
      FooterActionButton(title: primaryTitle, primary: true, action: primary)
        .keyboardShortcut(.defaultAction).disabled(isWorking || primaryDisabled)
    }.padding(.horizontal, 24).frame(height: 64).background(Palette.chrome)
      .overlay(alignment: .top) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
  }
}

private struct FooterActionButton: View {
  let title: String
  let primary: Bool
  let action: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
        .padding(.horizontal, 16).frame(minWidth: 72, minHeight: 34)
        .contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
    }.buttonStyle(FooterActionStyle(primary: primary)).focused($focused)
      .overlay {
        if focused && enabled {
          RoundedRectangle(cornerRadius: UILayout.controlRadius + 3, style: .continuous)
            .stroke(Palette.blue.opacity(0.55), lineWidth: 2).padding(-3).allowsHitTesting(false)
        }
      }
  }
}

private struct FooterActionStyle: ButtonStyle {
  let primary: Bool
  func makeBody(configuration: Configuration) -> some View {
    FeedbackBody(configuration: configuration, primary: primary)
  }

  private struct FeedbackBody: View {
    let configuration: Configuration
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovered = false

    var body: some View {
      let shape = RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous)
      configuration.label.foregroundStyle(primary ? Color.white : Palette.ink)
        .background(primary ? Palette.blue : Palette.paper, in: shape)
        .overlay {
          shape.fill(
            Color.black.opacity(
              !enabled
                ? 0
                : configuration.isPressed
                  ? (primary ? 0.16 : 0.07) : hovered ? (primary ? 0.08 : 0.025) : 0
            )
          ).allowsHitTesting(false)
        }
        .overlay { if !primary { shape.strokeBorder(Palette.border, lineWidth: 1) } }
        .opacity(enabled ? 1 : 0.4).onHover { hovered = $0 }
        .animation(UIMotion.feedback(reduceMotion), value: hovered)
        .animation(UIMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
  }
}
