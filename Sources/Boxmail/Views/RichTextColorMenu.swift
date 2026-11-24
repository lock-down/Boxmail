import BoxmailCore
import SwiftUI

struct RichTextColorMenu: View {
  static let colors: [(title: String, hex: String?)] = [
    ("默认", nil), ("黑色", "#000000"), ("灰色", "#606E82"), ("红色", "#B42318"),
    ("橙色", "#BF5700"), ("绿色", "#28745B"), ("蓝色", "#3567AF"), ("紫色", "#6941C6"),
  ]
  let color: String?
  let mixed: Bool
  let onSelect: (String?) -> Void
  let onCustom: () -> Void

  private var description: String {
    mixed ? "混合颜色" : Self.colors.first { $0.hex == color }?.title ?? color ?? "默认"
  }

  @CossMenuItems var menuItems: [CossMenuItem] {
    for option in Self.colors {
      CossMenuItem.command(option.title, swatch: Color(nsColor: RichTextStyle.nsColor(option.hex)),
        mark: .choice(!mixed && color == option.hex)) { onSelect(option.hex) }
    }
    CossMenuItem.divider
    CossMenuItem.command("自定颜色…", icon: .paletteLine, action: onCustom)
  }

  var body: some View {
    CossMenu(title: "文字颜色", value: description, emphasis: .secondary, prefersSelection: true) {
      menuItems
    } trigger: {
      let color = Color(nsColor: RichTextStyle.nsColor(color)).opacity(mixed ? 0.4 : 1)
      CossMenuLabel(title: "颜色", swatch: color, size: .compact)
    }.cossTooltip("文字颜色：\(description)")
  }
}
