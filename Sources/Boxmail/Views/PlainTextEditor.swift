import AppKit
import BoxmailCore
import SwiftUI

/// Keep placeholder text and the insertion point in the same native text container.
struct PlainTextEditor: NSViewRepresentable {
  @Binding var text: String
  var placeholder = ""
  var fontSize: CGFloat = 12
  var lineSpacing: CGFloat = 0
  var inset = NSSize(width: 12, height: 12)
  var accessibilityLabel: String
  var bottomAnchoredText = ""
  var onPaste: ((NSPasteboard) -> Bool)?
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
    if MailSignature.trailingRange(in: text, signature: bottomAnchoredText) != nil {
      textView.setSelectedRange(NSRange(location: 0, length: 0))
    }
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
    textView.updateBottomAnchor()
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
    textView.bottomAnchoredText = bottomAnchoredText
    textView.onPaste = onPaste
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
    guard let textView = documentView as? PlaceholderTextView else { return }
    let viewport = contentSize
    if textView.minSize.height != viewport.height {
      textView.minSize = NSSize(width: 0, height: viewport.height)
    }
    if textView.frame.width != viewport.width || textView.frame.height < viewport.height {
      textView.setFrameSize(
        NSSize(
          width: viewport.width, height: max(textView.frame.height, viewport.height)))
    }
    textView.updateBottomAnchor()
  }
}

private final class PlaceholderTextView: NSTextView {
  var placeholder = ""
  var bottomAnchoredText = ""
  var onPaste: ((NSPasteboard) -> Bool)?
  private var anchorInput: AnchorInput?
  private var updatingAnchor = false
  private var hasAnchorSpacing = false

  private struct AnchorInput: Equatable {
    let text, signature: String
    let viewport, inset: NSSize
    let fontSize, lineSpacing: CGFloat
  }

  /// The signature stays editable in the same text view. Only layout attributes change;
  /// the saved/sent body never acquires spacer lines or a second copy of the signature.
  func updateBottomAnchor() {
    guard !updatingAnchor, !hasMarkedText(), let scrollView = enclosingScrollView,
      let storage = textStorage, let manager = layoutManager, let container = textContainer else { return }
    let input = AnchorInput(text: string, signature: bottomAnchoredText,
      viewport: scrollView.contentSize, inset: textContainerInset,
      fontSize: font?.pointSize ?? 12, lineSpacing: defaultParagraphStyle?.lineSpacing ?? 0)
    guard input != anchorInput else { return }
    anchorInput = input
    updatingAnchor = true
    defer { updatingAnchor = false }
    let paragraph = defaultParagraphStyle ?? NSParagraphStyle.default
    if hasAnchorSpacing {
      storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
      hasAnchorSpacing = false
    }
    typingAttributes[.paragraphStyle] = paragraph
    guard let signature = MailSignature.trailingRange(in: string, signature: bottomAnchoredText) else { return }
    manager.ensureLayout(for: container)
    let gap = floor(max(0, input.viewport.height - input.inset.height * 2 - manager.usedRect(for: container).maxY))
    guard gap > 0 else { return }
    let anchored = paragraph.mutableCopy() as! NSMutableParagraphStyle
    anchored.paragraphSpacingBefore = gap
    let range = (string as NSString).paragraphRange(for: NSRange(location: signature.location, length: 0))
    storage.addAttribute(.paragraphStyle, value: anchored, range: range)
    hasAnchorSpacing = true
    manager.ensureLayout(for: container)
  }

  override func paste(_ sender: Any?) {
    if isEditable, onPaste?(.general) == true { return }
    super.paste(sender)
  }

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
    updateBottomAnchor()
    needsDisplay = true
  }
}
