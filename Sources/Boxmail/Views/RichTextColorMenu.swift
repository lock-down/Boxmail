import AppKit
import BoxmailCore
import SwiftUI

/// AppKit owns menu tracking and checkmarks; non-template images retain each sRGB swatch.
struct RichTextColorMenu: NSViewRepresentable {
  static let colors: [(title: String, hex: String?)] = [
    ("默认", nil), ("黑色", "#000000"), ("灰色", "#606E82"), ("红色", "#B42318"),
    ("橙色", "#BF5700"), ("绿色", "#28745B"), ("蓝色", "#3567AF"), ("紫色", "#6941C6"),
  ]
  let color: String?
  let mixed: Bool
  let onSelect: (String?) -> Void
  let onCustom: () -> Void

  func makeNSView(context: Context) -> RichTextColorButton {
    RichTextColorButton(frame: .zero, pullsDown: true)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: RichTextColorButton, context: Context)
    -> CGSize?
  {
    CGSize(width: UILayout.iconControl, height: UILayout.iconControl)
  }

  func updateNSView(_ button: RichTextColorButton, context: Context) {
    button.update(
      color: color, mixed: mixed, enabled: context.environment.isEnabled,
      onSelect: onSelect, onCustom: onCustom)
  }
}

@MainActor final class RichTextColorButton: SelectionControlButton {
  private var color: String?
  private var mixed = false
  private var onSelect: ((String?) -> Void)?
  private var onCustom: (() -> Void)?

  override var intrinsicContentSize: NSSize {
    NSSize(width: UILayout.iconControl, height: UILayout.iconControl)
  }

  override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
    super.init(frame: buttonFrame, pullsDown: flag)
    isBordered = false
    focusRingType = .none
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.font = .systemFont(ofSize: 12)
    menu.addItem(NSMenuItem(title: "文字颜色", action: nil, keyEquivalent: ""))
    for (index, option) in RichTextColorMenu.colors.enumerated() {
      let item = NSMenuItem(
        title: option.title, action: #selector(selectColor(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.image = Self.swatch(option.hex)
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let custom = NSMenuItem(title: "自定颜色…", action: #selector(selectCustomColor), keyEquivalent: "")
    custom.target = self
    menu.addItem(custom)
    self.menu = menu
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(
    color: String?, mixed: Bool, enabled: Bool,
    onSelect: @escaping (String?) -> Void, onCustom: @escaping () -> Void
  ) {
    self.color = color
    self.mixed = mixed
    self.onSelect = onSelect
    self.onCustom = onCustom
    isEnabled = enabled
    for (index, option) in RichTextColorMenu.colors.enumerated() {
      menu?.item(at: index + 1)?.state = !mixed && color == option.hex ? .on : .off
    }
    let description =
      mixed ? "混合颜色" : RichTextColorMenu.colors.first { $0.hex == color }?.title ?? color ?? "默认"
    setAccessibilityLabel("文字颜色")
    setAccessibilityValue(description)
    toolTip = "文字颜色：\(description)"
    needsDisplay = true
  }

  @objc private func selectColor(_ item: NSMenuItem) {
    guard isEnabled, RichTextColorMenu.colors.indices.contains(item.tag) else { return }
    onSelect?(RichTextColorMenu.colors[item.tag].hex)
  }

  @objc private func selectCustomColor() {
    guard isEnabled else { return }
    onCustom?()
  }

  override func draw(_ dirtyRect: NSRect) {
    drawIconSurface()
    let opacity: CGFloat = isEnabled ? 1 : 0.45
    let symbol = NSImage(systemSymbolName: "a", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: UILayout.iconSize, weight: .regular))?
      .withSymbolConfiguration(.init(paletteColors: [NSColor(Palette.muted)]))
    if let symbol {
      let size = symbol.size
      symbol.draw(
        in: NSRect(
          x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 - 1,
          width: size.width, height: size.height), from: .zero, operation: .sourceOver,
        fraction: opacity, respectFlipped: true, hints: nil)
    }
    RichTextStyle.nsColor(color).withAlphaComponent(opacity * (mixed ? 0.4 : 1)).setFill()
    NSRect(
      x: (bounds.width - UILayout.iconSize) / 2, y: bounds.height - 7,
      width: UILayout.iconSize, height: 2
    ).fill()
  }

  static func swatch(_ hex: String?) -> NSImage {
    let color = RichTextStyle.nsColor(hex)
    let context = CGContext(
      data: nil, width: 28, height: 28, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(
      red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 1)
    context.fillEllipse(in: CGRect(x: 2, y: 2, width: 24, height: 24))
    let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 14, height: 14))
    image.isTemplate = false
    return image
  }
}
