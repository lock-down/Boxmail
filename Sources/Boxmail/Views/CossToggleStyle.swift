import SwiftUI

struct CossCheckbox: View {
  let isOn: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 4)
    shape.fill(isOn ? Palette.primary : Palette.paper)
      .overlay { shape.strokeBorder(isOn ? Palette.primary : Palette.border, lineWidth: 1) }
      .overlay {
        if isOn {
          RemixIcon(.checkLine, size: 9)
            .foregroundStyle(Palette.primaryForeground)
        }
      }.frame(width: 16, height: 16)
  }
}

struct CossToggleStyle: ToggleStyle {
  var isSwitch = false
  var showsLabel = true

  func makeBody(configuration: Configuration) -> some View {
    Control(configuration: configuration, isSwitch: isSwitch, showsLabel: showsLabel)
  }

  private struct Control: View {
    let configuration: ToggleStyleConfiguration
    let isSwitch: Bool
    let showsLabel: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      Button { configuration.isOn.toggle() } label: {
        HStack(spacing: 8) {
          if isSwitch {
            Capsule().fill(configuration.isOn ? Palette.primary : Palette.border)
              .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(Palette.paper).frame(width: 14, height: 14).padding(2)
              }
              .frame(width: 32, height: 18)
              .animation(UIMotion.feedback(reduceMotion), value: configuration.isOn)
          } else {
            CossCheckbox(isOn: configuration.isOn)
          }
          if showsLabel { configuration.label }
        }.contentShape(Rectangle())
      }
      .buttonStyle(.plain).controlFocus()
      .opacity(enabled ? 1 : ControlStateAppearance.disabledOpacity)
      .accessibilityRepresentation {
        if isSwitch {
          Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        } else {
          Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        }
      }
    }
  }
}
