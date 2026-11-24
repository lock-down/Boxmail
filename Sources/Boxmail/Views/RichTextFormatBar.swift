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
    HStack(spacing: 8) {
      formatButton(.bold, help: "粗体（Command-B）", selected: controller.bold) {
        controller.toggleBold()
      }
      CossSeparator(axis: .vertical).frame(height: 18)
      HStack(spacing: 4) {
        fontSizeMenu
        colorMenu
      }
      CossSeparator(axis: .vertical).frame(height: 18)
      HStack(spacing: UILayout.iconGap) {
        formatButton(.listUnordered, help: "项目符号列表", selected: controller.list == "bullet") {
          controller.toggleList("bullet")
        }
        formatButton(.listOrdered, help: "编号列表", selected: controller.list == "numbered") {
          controller.toggleList("numbered")
        }
        IconButton(icon: .link, help: "添加链接（Command-K）") { showingLink = true }
          .cossPopover(isPresented: $showingLink) { linkEditor }
      }
    }.accessibilityElement(children: .contain).accessibilityLabel("富文本格式")
  }

  private var fontSizeMenu: some View {
    let size = controller.fontSize.map { $0.formatted(.number.grouping(.never)) + " pt" } ?? "混合字号"
    return CossMenu(title: "字号", value: size, width: 148, emphasis: .secondary, prefersSelection: true) {
      if controller.fontSize == nil { CossMenuItem.note("当前选区包含多个字号") }
      for value in sizeOptions {
        CossMenuItem.command(value.formatted(.number.grouping(.never)) + " pt",
          mark: .choice(value == controller.fontSize)) { controller.setFontSize(value) }
      }
    } trigger: {
      CossMenuLabel(title: size, icon: .fontSize, size: .compact)
    }.fixedSize()
  }

  private var sizeOptions: [Double] {
    var sizes = RichTextStyle.fontSizes
    if let current = controller.fontSize, !sizes.contains(current) {
      sizes.append(current)
      sizes.sort()
    }
    return sizes
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
    .cossPopover(isPresented: $showingColor) {
      VStack(alignment: .leading, spacing: 12) {
        Text("自定文字颜色").font(UIType.section).accessibilityAddTraits(.isHeader)
        CossColorEditor(hex: $customHex, fallbackHex: RichTextStyle.defaultColor, submit: applyCustomColor)
        HStack {
          ActionButton(title: "取消") { showingColor = false }
          Spacer()
          ActionButton(title: "应用颜色", emphasis: .primary) {
            applyCustomColor()
          }.disabled(!validCustomColor)
        }
      }.padding(16).frame(width: 320)
    }
  }

  private var validCustomColor: Bool { CategoryTone.canonicalHex(customHex) != nil }

  private func applyCustomColor() {
    guard let color = CategoryTone.canonicalHex(customHex) else { return }
    controller.setColor(color)
    showingColor = false
  }

  private func formatButton(
    _ icon: RemixGlyph, help: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    IconButton(
      icon: icon, help: help, color: selected ? Palette.accent : Palette.muted,
      selected: selected, action: action
    )
  }

  private var linkEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("添加链接").font(UIType.section).accessibilityAddTraits(.isHeader)
      WorkflowField(title: "链接地址") {
        WorkflowTextInput(label: "链接地址", placeholder: "https://example.com", text: $link)
          .onSubmit { insertLink() }
      }
      if let linkError { WorkflowNotice(text: linkError, icon: .errorWarningLine, color: Palette.destructive) }
      HStack {
        ActionButton(title: "取消") { showingLink = false }
        Spacer()
        ActionButton(title: "插入链接", icon: .link, emphasis: .primary) { insertLink() }
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
