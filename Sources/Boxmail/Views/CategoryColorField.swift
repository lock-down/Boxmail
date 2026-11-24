import SwiftUI

struct CategoryColorField: View {
  @Binding var hex: String
  let name: String

  private var validHex: String? { CategoryTone.canonicalHex(hex) }
  @ViewState private var editingColor = false
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
              .cossTooltip(preset.name).accessibilityLabel(preset.name)
              .accessibilityAddTraits(validHex == preset.hex ? .isSelected : [])
          }
        }
        HStack(spacing: 8) {
          Button { editingColor.toggle() } label: {
            CossMenuLabel(title: "自定义颜色", icon: .paletteLine, size: .compact)
          }.buttonStyle(ControlFeedback(emphasis: .secondary)).controlFocus()
            .cossPopover(isPresented: $editingColor) {
              VStack(alignment: .leading, spacing: 12) {
                Text("自定义标签颜色").font(UIType.section).accessibilityAddTraits(.isHeader)
                CossColorEditor(hex: $hex, fallbackHex: "#607084")
                HStack {
                  Spacer()
                  ActionButton(title: "完成", emphasis: .primary) { editingColor = false }
                    .disabled(validHex == nil)
                }
              }.padding(16).frame(width: 320)
            }
          WorkflowTextInput(label: "颜色十六进制值", placeholder: "#RRGGBB", text: $hex,
            font: .system(size: 12, design: .monospaced)).frame(width: 112)
            .cossTooltip("输入六位十六进制色值，可省略井号")
          Spacer(minLength: 0)
        }.font(UIType.caption)
        if let validHex { Tag(text: name.isEmpty ? "标签预览" : name, tone: CategoryTone(hex: validHex)) }
      }
    }
  }
}
