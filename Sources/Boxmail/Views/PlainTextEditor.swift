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
  var showsVerticalScroller = true
  var onPaste: ((NSPasteboard) -> Bool)?
  var submitShortcut: TextSubmitShortcut?
  var onSubmit: (() -> Void)?
  @Environment(\.isEnabled) private var enabled

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = EditorScrollView()
    ScrollAppearance.apply(to: scrollView)
    scrollView.hasVerticalScroller = showsVerticalScroller
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
    textView.insertionPointColor = NSColor(Palette.accent)
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor(Palette.accentSoft), .foregroundColor: NSColor(Palette.ink),
    ]
    if textView.textContainerInset != inset { textView.textContainerInset = inset }
    textView.placeholder = placeholder
    textView.bottomAnchoredText = bottomAnchoredText
    textView.onPaste = onPaste
    textView.submitShortcut = submitShortcut
    textView.onSubmit = onSubmit
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

final class EditorScrollView: NSScrollView {
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

class PlaceholderTextView: NSTextView {
  var placeholder = ""
  var bottomAnchoredText = ""
  var anchoredSignatureStart: Int?
  var showsSignatureSeparator: Bool { false }
  var onPaste: ((NSPasteboard) -> Bool)?
  var submitShortcut: TextSubmitShortcut?
  var onSubmit: (() -> Void)?
  private var anchorInput: AnchorInput?
  private var updatingAnchor = false
  private let signatureSeparatorSpacing: CGFloat = 24
  private let signatureSeparatorHeight: CGFloat = 17

  private struct AnchorInput: Equatable {
    let text: String
    let signatureStart: Int?
    let viewport, inset: NSSize
    let fontSize, lineSpacing: CGFloat
  }

  var signatureRange: NSRange? {
    MailSignature.trailingRange(in: string, startingAt: anchoredSignatureStart)
      ?? MailSignature.trailingRange(in: string, signature: bottomAnchoredText)
  }

  /// The signature stays editable in the same text view. Only layout attributes change;
  /// the saved/sent body never acquires spacer lines or a second copy of the signature.
  func updateBottomAnchor() {
    guard !updatingAnchor, !hasMarkedText(), let scrollView = enclosingScrollView,
      let storage = textStorage, let manager = layoutManager, let container = textContainer else { return }
    let input = AnchorInput(text: string, signatureStart: signatureRange?.location,
      viewport: scrollView.contentSize, inset: textContainerInset,
      fontSize: font?.pointSize ?? 12, lineSpacing: defaultParagraphStyle?.lineSpacing ?? 0)
    guard input != anchorInput else { return }
    anchorInput = input
    updatingAnchor = true
    defer {
      updatingAnchor = false
      if showsSignatureSeparator { needsDisplay = true }
    }
    let paragraph = defaultParagraphStyle ?? NSParagraphStyle.default
    // Undo can restore layout attributes independently of the cached anchor state.
    let key = NSAttributedString.Key("BoxmailAnchorParagraph")
    var originals: [(NSRange, NSParagraphStyle)] = []
    storage.enumerateAttribute(key, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
      if let original = value as? NSParagraphStyle { originals.append((range, original)) }
    }
    for (range, original) in originals { storage.addAttribute(.paragraphStyle, value: original, range: range) }
    if !originals.isEmpty {
      storage.removeAttribute(key, range: NSRange(location: 0, length: storage.length))
    }
    if isRichText, let current = typingAttributes[.paragraphStyle] as? NSParagraphStyle {
      let typing = current.mutableCopy() as! NSMutableParagraphStyle
      typing.paragraphSpacingBefore = 0
      typingAttributes[.paragraphStyle] = typing
    } else { typingAttributes[.paragraphStyle] = paragraph }
    guard let signature = signatureRange, signature.location > 0 || showsSignatureSeparator else { return }
    manager.ensureLayout(for: container)
    let minimumGap = showsSignatureSeparator ? signatureSeparatorSpacing : 0
    let gap = floor(max(minimumGap, input.viewport.height - input.inset.height * 2 - manager.usedRect(for: container).maxY))
    guard gap > 0 else { return }
    let range = (string as NSString).paragraphRange(for: NSRange(location: signature.location, length: 0))
    let original = (range.location < storage.length
      ? storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil) ?? paragraph
    let anchored = original.mutableCopy() as! NSMutableParagraphStyle
    anchored.paragraphSpacingBefore += gap
    storage.addAttribute(NSAttributedString.Key("BoxmailAnchorParagraph"), value: original, range: range)
    storage.addAttribute(.paragraphStyle, value: anchored, range: range)
    manager.ensureLayout(for: container)
  }

  override func characterIndexForInsertion(at point: NSPoint) -> Int {
    bodyInsertionIndex(inWhitespaceAt: point) ?? super.characterIndexForInsertion(at: point)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
    guard isSelectable, modifiers.isEmpty, var index = bodyInsertionIndex(inWhitespaceAt: point) else {
      super.mouseDown(with: event)
      return
    }
    // Leave composition to AppKit. Ordinary whitespace clicks place the caret directly.
    if hasMarkedText() {
      super.mouseDown(with: event)
      guard !hasMarkedText(), selectedRange().length == 0,
        let committedIndex = bodyInsertionIndex(inWhitespaceAt: point) else { return }
      index = committedIndex
    } else {
      window?.makeFirstResponder(self)
    }
    let caret = NSRange(location: index, length: 0)
    breakUndoCoalescing()
    setSelectedRange(caret)
    scrollRangeToVisible(caret)
  }

  private func lineRect(forCharacterAt index: Int) -> NSRect? {
    guard let manager = layoutManager, let container = textContainer else { return nil }
    manager.ensureLayout(for: container)
    let glyph = manager.glyphIndexForCharacter(at: index)
    let line = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    return line.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
  }

  private func signatureSeparator(at top: CGFloat) -> NSRect {
    let inset = textContainerOrigin.x
    return NSRect(x: inset, y: top - signatureSeparatorSpacing,
      width: max(0, bounds.width - inset * 2), height: signatureSeparatorHeight)
  }

  private func bodyInsertionIndex(inWhitespaceAt point: NSPoint) -> Int? {
    guard let start = signatureRange?.location, start > 0,
      let manager = layoutManager, let container = textContainer else { return nil }
    let source = string as NSString
    let bodyEnd = source.rangeOfComposedCharacterSequence(at: start - 1)
    guard let bodyLine = lineRect(forCharacterAt: bodyEnd.location) else { return nil }
    let emptyLine = source.paragraphRange(for: bodyEnd) == bodyEnd
    guard point.y >= (emptyLine ? bodyLine.minY : bodyLine.maxY) else { return nil }

    let origin = textContainerOrigin
    let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    let glyph = manager.glyphIndex(for: local, in: container)
    // TextKit returns the nearest glyph even for points far outside the signature text.
    if manager.characterIndexForGlyph(at: glyph) >= start,
      manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).contains(local) { return nil }
    return bodyEnd.location
  }

  override func paste(_ sender: Any?) {
    if isEditable, onPaste?(.general) == true { return }
    super.paste(sender)
  }

  override func keyDown(with event: NSEvent) {
    if isEditable, !hasMarkedText(), [36, 76].contains(event.keyCode), let submitShortcut {
      if submitShortcut.matches(event.modifierFlags), let onSubmit {
        onSubmit()
        return
      }
      let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if modifiers.isEmpty || modifiers == .shift {
        insertNewline(nil)
        return
      }
    }
    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if showsSignatureSeparator, let start = signatureRange?.location,
      let top = lineRect(forCharacterAt: start)?.minY {
      let rect = signatureSeparator(at: top)
      if dirtyRect.intersects(rect) {
        let label = NSAttributedString(string: "签名", attributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .medium),
          .foregroundColor: NSColor(Palette.muted),
        ])
        label.draw(at: NSPoint(x: rect.minX, y: rect.minY))
        let lineX = rect.minX + ceil(label.size().width) + 8
        NSColor(Palette.softBorder).setFill()
        NSRect(x: lineX, y: floor(rect.midY), width: max(0, rect.maxX - lineX), height: 1).fill()
      }
    }
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
    anchorInput = nil
    updateBottomAnchor()
    needsDisplay = true
  }
}
