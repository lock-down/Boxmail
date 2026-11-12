import BoxmailCore
import SwiftUI

struct RichTextFormatBar: View {
  let controller: RichTextController
  @Binding var showingLink: Bool
  @ViewState<String> private var link = "https://"
  @ViewState<String?> private var linkError = nil
  @ViewState<Bool> private var showingColor = false
  @ViewState<String> private var customHex = RichTextStyle.defaultColor

  var body: some View {
    HStack(spacing: UILayout.iconGap) {
      formatButton("bold", help: "粗体（Command-B）", selected: controller.bold) {
        controller.toggleBold()
      }
      colorMenu
      WorkflowSelection(
        title: "字号",
        selection: Binding(
          get: { controller.fontSize }, set: { if let size = $0 { controller.setFontSize(size) } }),
        options: sizeOptions, style: .toolbar,
        displayTitle: controller.fontSize == nil ? "混合" : nil
      ).frame(width: 64, height: UILayout.iconControl)
      formatButton("list.bullet", help: "项目符号列表", selected: controller.list == "bullet") {
        controller.toggleList("bullet")
      }
      formatButton("list.number", help: "编号列表", selected: controller.list == "numbered") {
        controller.toggleList("numbered")
      }
      IconButton(icon: "link", help: "添加链接（Command-K）") { showingLink = true }
        .popover(isPresented: $showingLink) { linkEditor }
    }
  }

  private var sizeOptions: [(Double?, String)] {
    var sizes = RichTextStyle.fontSizes
    if let current = controller.fontSize, !sizes.contains(current) {
      sizes.append(current)
      sizes.sort()
    }
    let options = sizes.map { (Optional($0), "\($0.formatted(.number.grouping(.never))) pt") }
    return controller.fontSize == nil ? [(nil, "混合字号")] + options : options
  }

  private var colorMenu: some View {
    RichTextColorMenu(
      color: controller.color, mixed: controller.hasMixedColor,
      onSelect: controller.setColor,
      onCustom: {
        customHex = controller.color ?? RichTextStyle.defaultColor
        showingColor = true
      }
    )
    .frame(width: UILayout.iconControl, height: UILayout.iconControl)
    .popover(isPresented: $showingColor) {
      VStack(alignment: .leading, spacing: 12) {
        Text("文字颜色").font(UIType.section)
        ColorPicker(
          "自定文字颜色",
          selection: Binding(
            get: { Color(nsColor: RichTextStyle.nsColor(customHex)) },
            set: { customHex = RichTextStyle.hexColor(NSColor($0)) ?? RichTextStyle.defaultColor }
          ), supportsOpacity: false)
        HStack {
          Text("色值").font(UIType.caption).foregroundStyle(Palette.muted)
          TextField("#RRGGBB", text: $customHex).settingsTextInput()
            .accessibilityLabel("十六进制色值").onSubmit { applyCustomColor() }
        }
        if !validCustomColor {
          Text("请输入 # 开头的六位色值。").font(UIType.small).foregroundStyle(Palette.amber)
        }
        HStack {
          ActionButton(title: "取消") { showingColor = false }
          Spacer()
          ActionButton(title: "应用颜色", kind: .primary) {
            applyCustomColor()
          }.disabled(!validCustomColor)
        }
      }.padding(16).frame(width: 260)
    }
  }

  private var validCustomColor: Bool {
    customHex.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
  }

  private func applyCustomColor() {
    guard validCustomColor else { return }
    controller.setColor(customHex)
    showingColor = false
  }

  private func formatButton(
    _ icon: String, help: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    IconButton(
      icon: icon, help: help, color: selected ? Palette.blue : Palette.muted,
      active: selected, action: action
    )
    .background(
      selected ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: UILayout.iconRadius)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var linkEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("添加链接").font(UIType.section)
      TextField("https://example.com", text: $link).settingsTextInput()
        .accessibilityLabel("链接地址").onSubmit { insertLink() }
      if let linkError { Text(linkError).font(UIType.small).foregroundStyle(Palette.amber) }
      HStack {
        ActionButton(title: "取消") { showingLink = false }
        Spacer()
        ActionButton(title: "插入链接", icon: "link", kind: .primary) { insertLink() }
      }
    }.padding(16).frame(width: 320)
  }

  private func insertLink() {
    guard controller.applyLink(link.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      linkError = "请输入完整的 HTTP、HTTPS 或 mailto 链接。"
      return
    }
    linkError = nil
    showingLink = false
  }
}
