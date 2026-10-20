import AppKit
import SwiftUI

/// Keep placeholder text and the insertion point in the same native text container.
struct PlainTextEditor: NSViewRepresentable {
  @Binding var text: String
  var placeholder = ""
  var fontSize: CGFloat = 12
  var lineSpacing: CGFloat = 0
  var inset = NSSize(width: 12, height: 12)
  var accessibilityLabel: String
  @Environment(\.isEnabled) private var enabled

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = EditorScrollView()
    ScrollAppearance.apply(to: scrollView)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false

    let textView = PlaceholderTextView(frame: scrollView.contentView.bounds)
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.lineFragmentPadding = 0
    textView.delegate = context.coordinator
    scrollView.documentView = textView
    configure(textView)
    textView.string = text
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    ScrollAppearance.apply(to: scrollView)
    context.coordinator.text = $text
    guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
    configure(textView)
    if textView.string != text && !textView.hasMarkedText() {
      let selection = textView.selectedRange()
      textView.string = text
      textView.setSelectedRange(
        NSRange(location: min(selection.location, text.utf16.count), length: 0))
    }
    textView.needsDisplay = true
  }

  private func configure(_ textView: PlaceholderTextView) {
    let font = NSFont.systemFont(ofSize: fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    if textView.font != font || textView.defaultParagraphStyle?.lineSpacing != lineSpacing {
      textView.font = font
      textView.defaultParagraphStyle = paragraph
      textView.typingAttributes = [
        .font: font, .foregroundColor: NSColor(Palette.ink), .paragraphStyle: paragraph,
      ]
    }
    textView.textColor = NSColor(Palette.ink)
    textView.insertionPointColor = NSColor(Palette.blue)
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor(Palette.blueSoft), .foregroundColor: NSColor(Palette.ink),
    ]
    if textView.textContainerInset != inset { textView.textContainerInset = inset }
    textView.placeholder = placeholder
    textView.isEditable = enabled
    textView.setAccessibilityLabel(accessibilityLabel)
  }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    (scrollView.documentView as? NSTextView)?.delegate = nil
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }
    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}

private final class EditorScrollView: NSScrollView {
  override func layout() {
    super.layout()
    ScrollAppearance.apply(to: self)
    guard let textView = documentView as? NSTextView else { return }
    let viewport = contentSize
    if textView.minSize.height != viewport.height {
      textView.minSize = NSSize(width: 0, height: viewport.height)
    }
    if textView.frame.width != viewport.width || textView.frame.height < viewport.height {
      textView.setFrameSize(
        NSSize(
          width: viewport.width, height: max(textView.frame.height, viewport.height)))
    }
  }
}

private final class PlaceholderTextView: NSTextView {
  var placeholder = ""

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? .systemFont(ofSize: 12),
      .foregroundColor: NSColor(Palette.muted),
      .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
    ]
    let origin = textContainerOrigin
    NSAttributedString(string: placeholder, attributes: attributes).draw(
      with: NSRect(
        x: origin.x, y: origin.y, width: max(0, bounds.width - origin.x * 2),
        height: max(0, bounds.height - origin.y)),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
  }

  override func didChangeText() {
    super.didChangeText()
    needsDisplay = true
  }
}
