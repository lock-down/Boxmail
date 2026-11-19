import SwiftUI

struct CategoryColorField: View {
  @Binding var hex: String
  let name: String

  private var validHex: String? { CategoryTone.canonicalHex(hex) }
  private var selection: Binding<Color> {
    Binding(get: { CategoryTone(hex: validHex ?? "#607084").swatch }, set: { color in
      if let value = CategoryTone.hex(for: color) { hex = value }
    })
  }

  var body: some View {
    WorkflowField(title: "标签颜色") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          ForEach(CategoryTone.presets) { preset in
            Button { hex = preset.hex } label: {
              Circle().fill(preset.color).frame(width: 16, height: 16)
                .frame(width: 24, height: 28)
                .overlay {
                  if validHex == preset.hex {
                    Circle().strokeBorder(Palette.ink, lineWidth: 1).frame(width: 23, height: 23)
                  }
                }.contentShape(Rectangle())
            }.buttonStyle(ControlFeedback()).controlFocus()
              .help(preset.name).accessibilityLabel(preset.name)
              .accessibilityAddTraits(validHex == preset.hex ? .isSelected : [])
          }
        }
        HStack(spacing: 8) {
          ColorPicker("自定义颜色", selection: selection, supportsOpacity: false)
            .fixedSize(horizontal: true, vertical: false)
          TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced)).frame(width: 80)
            .foregroundStyle(validHex == nil && !hex.isEmpty ? Palette.amber : Palette.ink)
            .accessibilityLabel("颜色十六进制值").help("输入六位十六进制色值，可省略井号")
          Spacer(minLength: 4)
          if let validHex { Tag(text: name.isEmpty ? "标签预览" : name, tone: CategoryTone(hex: validHex)) }
        }.font(UIType.caption)
      }
    }
  }
}
