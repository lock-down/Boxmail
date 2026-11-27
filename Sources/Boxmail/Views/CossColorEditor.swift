import AppKit
import SwiftUI

struct CossColorEditor: View {
  @Binding var hex: String
  let fallbackHex: String
  var submit: () -> Void = {}

  private enum Channel: Int, CaseIterable, Identifiable {
    case red = 16, green = 8, blue = 0

    var id: Self { self }

    var title: String {
      switch self {
      case .red: return "红"
      case .green: return "绿"
      case .blue: return "蓝"
      }
    }
  }

  private var validHex: String? { CategoryTone.canonicalHex(hex) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        let shape = RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous)
        shape.fill(CategoryTone(hex: validHex ?? fallbackHex).swatch)
          .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
          .frame(width: UIControlSize.form.height, height: UIControlSize.form.height)
          .accessibilityHidden(true)
        WorkflowTextInput(label: "十六进制色值", placeholder: "#RRGGBB", text: $hex,
          font: .system(size: 12, design: .monospaced))
          .onSubmit(submit)
        IconButton(icon: .colorPicker, help: "从屏幕取色", size: UIControlSize.form.height) {
          NSColorSampler().show { color in
            if let color, let hex = CategoryTone.hex(for: Color(nsColor: color)) { self.hex = hex }
          }
        }
      }
      ForEach(Channel.allCases) { channel in
        HStack(spacing: 12) {
          Text(channel.title).font(UIType.caption).foregroundStyle(Palette.muted)
            .frame(width: 16, alignment: .leading).accessibilityHidden(true)
          ColorChannelSlider(title: channel.title + "色分量", value: component(channel))
          CossNumberField(title: channel.title + "色数值", value: component(channel), range: 0...255)
            .frame(width: 108)
        }
      }
      if validHex == nil {
        Text("请输入六位十六进制色值。").font(UIType.small).foregroundStyle(Palette.destructive)
      }
    }
  }

  private func component(_ channel: Channel) -> Binding<Int> {
    let shift = channel.rawValue
    return Binding(get: { Int((rgb >> shift) & 0xFF) }, set: { value in
      let mask = UInt32(0xFF) << shift
      hex = String(format: "#%06X", (rgb & ~mask) | (UInt32(value) << shift))
    })
  }

  private var rgb: UInt32 { UInt32((validHex ?? fallbackHex).dropFirst(), radix: 16) ?? 0 }
}

private struct ColorChannelSlider: View {
  let title: String
  @Binding var value: Int
  @FocusState private var focused: Bool
  private let thumb: CGFloat = 16

  var body: some View {
    GeometryReader { geometry in
      let travel = geometry.size.width - thumb
      let offset = travel * CGFloat(value) / 255
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.selected).frame(height: 4)
          .overlay(alignment: .leading) {
            Capsule().fill(Palette.primary).frame(width: offset + thumb / 2)
          }
        Circle().fill(Palette.paper)
          .overlay { Circle().strokeBorder(Palette.primary, lineWidth: 1.5) }
          .overlay {
            if focused { Circle().strokeBorder(Palette.accent, lineWidth: 2).padding(-2) }
          }
          .frame(width: thumb, height: thumb).offset(x: offset)
      }.frame(maxHeight: .infinity).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
          let fraction = (drag.location.x - thumb / 2) / travel
          value = Int((min(1, max(0, fraction)) * 255).rounded())
        })
    }.frame(minWidth: 80, minHeight: 28, maxHeight: 28)
      .focusable().focusEffectDisabled().focused($focused)
      .onKeyPress(.leftArrow) { value = max(0, value - 1); return .handled }
      .onKeyPress(.rightArrow) { value = min(255, value + 1); return .handled }
      .accessibilityRepresentation {
        Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
          in: 0...255, step: 1) { Text(title) }
      }
  }
}
