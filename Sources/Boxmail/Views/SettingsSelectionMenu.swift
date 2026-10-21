import AppKit
import SwiftUI

enum SettingsSelectionItem {
  case choice(String, selected: Bool, action: () -> Void)
  case note(String)
  case separator
}

struct SettingsSelectionGroup {
  let title: String
  let value: String
  let items: [SettingsSelectionItem]
}

struct SettingsSelectionMenu: NSViewRepresentable {
  let model: String
  let effort: String
  let groups: [SettingsSelectionGroup]

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> SelectionButton {
    let button = SelectionButton(frame: .zero, pullsDown: true)
    button.isBordered = false
    button.focusRingType = .none
    button.setAccessibilityLabel("模型与思考等级")
    return button
  }
  func updateNSView(_ button: SelectionButton, context: Context) {
    button.model = model
    button.effort = effort
    button.setAccessibilityValue(model + "，" + effort)
    button.menu = context.coordinator.makeMenu(groups)
    button.needsDisplay = true
  }

  @MainActor final class Coordinator: NSObject {
    private final class ItemAction: NSObject {
      let run: () -> Void
      init(_ run: @escaping () -> Void) { self.run = run; super.init() }
    }

    func makeMenu(_ groups: [SettingsSelectionGroup]) -> NSMenu {
      let menu = NSMenu()
      menu.autoenablesItems = false
      menu.font = .systemFont(ofSize: 12)
      menu.showsStateColumn = false
      menu.minimumWidth = 228
      // Pull-down buttons reserve their first item for the control's title.
      menu.addItem(NSMenuItem(title: "模型与思考等级", action: nil, keyEquivalent: ""))
      for group in groups {
        let value = compactTitle(group.value, width: 128)
        let title = group.title + "\t" + value
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.toolTip = value == group.value ? nil : group.value
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 184)]
        let text = NSMutableAttributedString(
          string: title,
          attributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph])
        text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: (group.title as NSString).length + 1,
            length: (title as NSString).length - (group.title as NSString).length - 1))
        item.attributedTitle = text
        item.submenu = submenu(group.items)
        menu.addItem(item)
      }
      return menu
    }

    private func submenu(_ items: [SettingsSelectionItem]) -> NSMenu {
      let menu = NSMenu()
      menu.autoenablesItems = false
      menu.font = .systemFont(ofSize: 12)
      for choice in items {
        switch choice {
        case .separator:
          menu.addItem(.separator())
        case .note(let title):
          let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
          item.isEnabled = false
          menu.addItem(item)
        case .choice(let title, let selected, let action):
          let label = compactTitle(title, width: 200)
          let item = NSMenuItem(title: label, action: #selector(selectItem(_:)), keyEquivalent: "")
          item.target = self
          item.representedObject = ItemAction(action)
          item.toolTip = label == title ? nil : title
          item.state = selected ? .on : .off
          menu.addItem(item)
        }
      }
      return menu
    }

    private func compactTitle(_ title: String, width: CGFloat) -> String {
      let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
      var limit = min(title.count, 48)
      var label = menuTitle(title, limit: limit)
      while limit > 12 && (label as NSString).size(withAttributes: attributes).width > width {
        limit -= 1
        label = menuTitle(title, limit: limit)
      }
      return label
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
      guard let action = sender.representedObject as? ItemAction else { return }
      // Native tracking must finish before presenting the custom model editor.
      DispatchQueue.main.async { action.run() }
    }
  }

  @MainActor final class SelectionButton: NSPopUpButton {
    var model = ""
    var effort = ""
    override var isFlipped: Bool { true }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }

    override func draw(_ dirtyRect: NSRect) {
      let background = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
      NSColor(Palette.canvas).setFill()
      background.fill()
      if cell?.showsFirstResponder == true {
        NSColor(Palette.blue).setFill()
        NSBezierPath(rect: NSRect(x: 8, y: bounds.height - 1, width: max(0, bounds.width - 16), height: 1)).fill()
      }
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingMiddle
      let font = NSFont.systemFont(ofSize: 12)
      let y = (bounds.height - 16) / 2
      (model as NSString).draw(
        in: NSRect(x: 10, y: y, width: bounds.width - 92, height: 18),
        withAttributes: [.font: font, .foregroundColor: NSColor(Palette.ink), .paragraphStyle: paragraph])
      paragraph.alignment = .right
      (effort as NSString).draw(
        in: NSRect(x: bounds.width - 72, y: y, width: 42, height: 18),
        withAttributes: [.font: font, .foregroundColor: NSColor(Palette.muted), .paragraphStyle: paragraph])
      let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(paletteColors: [NSColor(Palette.muted)]))
      arrow?.draw(in: NSRect(x: bounds.width - 19, y: (bounds.height - 7) / 2, width: 9, height: 7),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
  }
}
