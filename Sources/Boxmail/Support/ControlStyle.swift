import SwiftUI

enum UIControlSize {
  case compact, regular, form

  var height: CGFloat {
    switch self {
    case .compact: return 28
    case .regular: return 32
    case .form: return 36
    }
  }

  var font: Font {
    .system(size: self == .compact ? 11 : 12, weight: .medium)
  }

  var horizontalInset: CGFloat { self == .compact ? 8 : 12 }
}

enum ButtonEmphasis {
  case plain, tinted, secondary, primary

  var surface: Color {
    switch self {
    case .plain: return .clear
    case .tinted: return Palette.blueSoft
    case .secondary: return Palette.paper
    case .primary: return Palette.blue
    }
  }
}

/// Shared by SwiftUI controls and their native AppKit counterparts.
enum ControlStateAppearance {
  static let disabledOpacity = 0.45
  static let focusOpacity = 0.65

  static func overlayOpacity(
    enabled: Bool, pressed: Bool, hovered: Bool, emphasis: ButtonEmphasis = .plain
  ) -> Double {
    guard enabled else { return 0 }
    if pressed { return emphasis == .primary ? 0.16 : 0.08 }
    return hovered ? emphasis == .primary ? 0.08 : 0.045 : 0
  }
}

/// One surface and hit shape for every button; labels own their content and layout.
struct ControlFeedback: ButtonStyle {
  var selected = false
  var emphasis: ButtonEmphasis = .plain
  var corner: CGFloat = UILayout.controlRadius

  func makeBody(configuration: Configuration) -> some View {
    FeedbackBody(configuration: configuration, selected: selected, emphasis: emphasis, corner: corner)
  }

  private struct FeedbackBody: View {
    let configuration: Configuration
    let selected: Bool
    let emphasis: ButtonEmphasis
    let corner: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovered = false

    private var shape: RoundedRectangle {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    var body: some View {
      configuration.label
        .background(emphasis.surface, in: shape)
        .contentShape(shape)
        .overlay {
          shape.fill(
            (selected ? Palette.blue : Palette.ink).opacity(
              ControlStateAppearance.overlayOpacity(
                enabled: enabled, pressed: configuration.isPressed, hovered: hovered, emphasis: emphasis)
            )
          ).allowsHitTesting(false)
        }
        .overlay {
          if emphasis == .secondary { shape.strokeBorder(Palette.border, lineWidth: 1) }
        }
        .opacity(enabled ? 1 : ControlStateAppearance.disabledOpacity)
        .onHover { hovered = $0 }
        .animation(UIMotion.feedback(reduceMotion), value: hovered)
        .animation(UIMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
  }
}

private struct ControlFocus: ViewModifier {
  let corner: CGFloat
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled

  func body(content: Content) -> some View {
    content.focused($focused).overlay {
      if focused && enabled {
        RoundedRectangle(cornerRadius: corner + 3, style: .continuous)
          .stroke(Palette.blue.opacity(ControlStateAppearance.focusOpacity), lineWidth: 2)
          .padding(-3).allowsHitTesting(false)
      }
    }
  }
}

extension View {
  /// Keep content centered within the same symmetric bounds used for feedback and focus.
  func controlLabel(
    size: UIControlSize = .regular, horizontalInset: CGFloat? = nil,
    verticalInset: CGFloat = 0, fillsWidth: Bool = false, alignment: Alignment = .center
  ) -> some View {
    padding(.horizontal, horizontalInset ?? size.horizontalInset)
      .padding(.vertical, verticalInset)
      .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.height, alignment: alignment)
  }

  func controlFocus(corner: CGFloat = UILayout.controlRadius) -> some View {
    modifier(ControlFocus(corner: corner))
  }
}
