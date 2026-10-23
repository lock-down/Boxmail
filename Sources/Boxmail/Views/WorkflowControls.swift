import AppKit
import SwiftUI

struct WorkflowPanelHeader: View {
  let title: String
  let subtitle: String
  let closeLabel: String
  let close: () -> Void
  var body: some View {
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(UIType.heading).foregroundStyle(Palette.ink)
        Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      WorkflowAction(title: "", icon: "xmark", help: closeLabel, action: close)
        .keyboardShortcut(.cancelAction)
    }
  }
}

struct WorkflowAction: View {
  let title: String
  var icon: String? = nil
  var color: Color = Palette.ink
  var help: String? = nil
  let action: () -> Void
  @ViewState<Bool> private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        if let icon {
          Image(systemName: icon).font(.system(size: 12, weight: .medium))
            .frame(width: 14).accessibilityHidden(true)
        }
        if !title.isEmpty { Text(title).underline(focused).lineLimit(1).fixedSize() }
      }.font(.system(size: 12, weight: .medium))
        .foregroundStyle(hovered || focused ? color == Palette.ink ? Palette.blue : color : color)
        .padding(.horizontal, 8).frame(height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(ControlFeedback(corner: 6)).focused($focused).onHover { hovered = $0 }
      .animation(UIMotion.feedback(reduceMotion), value: hovered)
      .help(help ?? title).accessibilityLabel(help ?? title)
  }
}

struct WorkflowField<Content: View>: View {
  let title: String
  var detail = ""
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title).font(UIType.caption).foregroundStyle(Palette.muted)
        Spacer(minLength: 4)
        if !detail.isEmpty { Text(detail).font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit() }
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WorkflowTextInput: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var lines = 1
  var font: Font = UIType.body
  var surface: Color = Palette.canvas
  @FocusState private var focused: Bool
  var body: some View {
    TextField("", text: $text, axis: lines > 1 ? .vertical : .horizontal)
      .textFieldStyle(.plain).font(font).foregroundStyle(Palette.ink)
      .lineLimit(1...lines).lineSpacing(lines > 1 ? 4 : 0).focused($focused)
      .padding(.horizontal, 10).padding(.vertical, lines > 1 ? 10 : 0)
      .frame(minHeight: lines > 1 ? 108 : SettingsFormLayout.controlHeight,
        maxHeight: lines > 1 ? nil : SettingsFormLayout.controlHeight,
        alignment: lines > 1 ? .topLeading : .leading)
      .background(surface, in: RoundedRectangle(cornerRadius: 7))
      .overlay(alignment: lines > 1 ? .topLeading : .leading) {
        if text.isEmpty {
          Text(placeholder).font(font).foregroundStyle(Palette.muted)
            .padding(.horizontal, 10).padding(.vertical, lines > 1 ? 10 : 0)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .overlay(alignment: .bottom) {
        if focused { Rectangle().fill(Palette.blue).frame(height: 1).padding(.horizontal, 8) }
      }.accessibilityLabel(label)
  }
}

struct WorkflowSelection<Value: Hashable>: NSViewRepresentable {
  let title: String
  @Binding var selection: Value
  let options: [(Value, String)]
  var compact = false

  func makeNSView(context: Context) -> WorkflowSelectionButton {
    let button = WorkflowSelectionButton(frame: .zero, pullsDown: false)
    button.isBordered = false
    button.focusRingType = .none
    button.target = button
    button.action = #selector(WorkflowSelectionButton.selectValue)
    return button
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkflowSelectionButton, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 160, height: 32)
  }
  func updateNSView(_ button: WorkflowSelectionButton, context: Context) {
    let labels = options.map(\.1)
    if button.itemTitles != labels {
      button.removeAllItems()
      button.addItems(withTitles: labels)
      button.menu?.font = .systemFont(ofSize: 12)
      for (index, item) in (button.itemArray).enumerated() { item.toolTip = labels[index] }
    }
    if let index = options.firstIndex(where: { $0.0 == selection }) { button.selectItem(at: index) }
    button.compact = compact
    button.isEnabled = context.environment.isEnabled
    button.setAccessibilityLabel(title)
    button.setAccessibilityValue(button.titleOfSelectedItem ?? "请选择")
    button.toolTip = button.titleOfSelectedItem
    let binding = $selection
    button.onSelect = { index in
      guard options.indices.contains(index) else { return }
      binding.wrappedValue = options[index].0
    }
    button.needsDisplay = true
  }
}

@MainActor final class WorkflowSelectionButton: NSPopUpButton {
  var compact = false
  var onSelect: ((Int) -> Void)?
  override var isFlipped: Bool { true }
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
  override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: SettingsFormLayout.controlHeight) }

  @objc func selectValue() { onSelect?(indexOfSelectedItem) }
  override func draw(_ dirtyRect: NSRect) {
    if !compact {
      NSColor(Palette.canvas).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
    if cell?.showsFirstResponder == true {
      NSColor(Palette.blue).setFill()
      NSBezierPath(rect: NSRect(x: 6, y: bounds.height - 1, width: max(0, bounds.width - 12), height: 1)).fill()
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    paragraph.alignment = .left
    let text = titleOfSelectedItem ?? "请选择"
    let font = NSFont.systemFont(ofSize: 12, weight: compact ? .medium : .regular)
    let textWidth = min(ceil((text as NSString).size(withAttributes: [.font: font]).width),
      max(0, bounds.width - 32))
    let inset: CGFloat = compact ? floor((bounds.width - textWidth - 16) / 2) : 10
    (text as NSString).draw(in: NSRect(x: inset, y: (bounds.height - 16) / 2,
      width: compact ? textWidth : max(0, bounds.width - inset - 22), height: 18), withAttributes: [
        .font: font,
        .foregroundColor: NSColor(isHighlighted ? Palette.blue : Palette.ink).withAlphaComponent(isEnabled ? 1 : 0.4),
        .paragraphStyle: paragraph,
      ])
    let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(paletteColors: [NSColor(Palette.muted)]))
    arrow?.draw(in: NSRect(x: compact ? inset + textWidth + 8 : bounds.width - 17,
      y: (bounds.height - 7) / 2, width: 8, height: 7),
      from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true, hints: nil)
  }
}

struct WorkflowStepper: View {
  let title: String
  @Binding var value: Int
  let range: ClosedRange<Int>
  let unit: String
  var body: some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      HStack(spacing: 8) {
        WorkflowAction(title: "", icon: "minus", help: "减少" + title) { value = max(range.lowerBound, value - 1) }
          .disabled(value <= range.lowerBound)
        Text(value.formatted(.number.grouping(.never))).font(UIType.caption).monospacedDigit().frame(minWidth: 24)
        WorkflowAction(title: "", icon: "plus", help: "增加" + title) { value = min(range.upperBound, value + 1) }
          .disabled(value >= range.upperBound)
        Text(unit).font(UIType.caption).foregroundStyle(Palette.muted)
        Spacer(minLength: 0)
      }
    }
  }
}

struct WorkflowNotice: View {
  let text: String
  var icon = "info.circle"
  var color: Color = Palette.muted
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon).frame(width: 14).padding(.top, 1)
      Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }.font(UIType.small).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
  }
}
