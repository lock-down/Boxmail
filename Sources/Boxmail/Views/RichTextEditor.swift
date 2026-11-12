import AppKit
import BoxmailCore
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var document: RichTextDocument?
  let controller: RichTextController
  let placeholder: String
  let accessibilityLabel: String
  let signature: String
  var onPaste: ((NSPasteboard) -> Bool)?
  var onLink: () -> Void
  @Environment(\.isEnabled) private var enabled

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = EditorScrollView()
    scroll.hasVerticalScroller = true
    let view = RichComposerTextView(frame: scroll.contentView.bounds)
    view.isRichText = true
    view.importsGraphics = false
    view.allowsUndo = true
    view.drawsBackground = false
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.minSize = .zero
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = true
    view.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.lineFragmentPadding = 0
    view.font = .systemFont(ofSize: RichTextStyle.defaultFontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    view.defaultParagraphStyle = paragraph
    view.typingAttributes = [
      .font: NSFont.systemFont(ofSize: RichTextStyle.defaultFontSize), .paragraphStyle: paragraph,
      .foregroundColor: RichTextStyle.nsColor(nil),
    ]
    view.textStorage?.setAttributedString(RichTextCodec.attributed(document ?? .init(text: text)))
    view.delegate = context.coordinator
    view.textStorage?.delegate = context.coordinator
    if let storage = view.textStorage { context.coordinator.resetProjection(storage) }
    view.setSelectedRange(NSRange(location: 0, length: 0))
    scroll.documentView = view
    configure(view)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    ScrollAppearance.apply(to: scroll)
    guard let view = scroll.documentView as? RichComposerTextView else { return }
    configure(view)
    if !view.hasMarkedText(),
      document != nil ? document != context.coordinator.lastDocument : text != view.string
    {
      let selection = view.selectedRange()
      let replacement = RichTextCodec.attributed(document ?? .init(text: text))
      let mapped = RichTextSelection.map(selection, from: view.attributedString(), to: replacement)
      view.textStorage?.setAttributedString(replacement)
      view.setSelectedRange(mapped)
      context.coordinator.lastDocument = document
      if let storage = view.textStorage { context.coordinator.resetProjection(storage) }
    }
    view.updateBottomAnchor()
    view.needsDisplay = true
  }
  private func configure(_ view: RichComposerTextView) {
    controller.textView = view
    view.controller = controller
    view.onLink = onLink
    view.onPaste = onPaste
    view.placeholder = placeholder
    view.bottomAnchoredText = signature
    view.textContainerInset = NSSize(width: 24, height: 18)
    view.insertionPointColor = NSColor(Palette.blue)
    view.linkTextAttributes = [
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]
    view.selectedTextAttributes = [
      .backgroundColor: NSColor(Palette.blueSoft), .foregroundColor: NSColor(Palette.ink),
    ]
    view.isEditable = enabled
    view.setAccessibilityLabel(accessibilityLabel)
  }
  static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
    (view.documentView as? NSTextView)?.delegate = nil
    (view.documentView as? NSTextView)?.textStorage?.delegate = nil
  }
  final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    var parent: RichTextEditor
    var lastDocument: RichTextDocument?
    private let projection = RichTextDocumentProjection()
    var changesParagraphs = false
    var editedRangeForLayout: NSRange? { characterEdits == 1 ? edit?.range : nil }
    private var characterEdits = 0
    private var edit: (range: NSRange, delta: Int)?
    func resetProjection(_ storage: NSTextStorage) {
      projection.reset(storage)
      characterEdits = 0
      edit = nil
      changesParagraphs = false
    }
    func textStorage(
      _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
      range editedRange: NSRange, changeInLength delta: Int
    ) {
      if editedMask.contains(.editedCharacters) {
        characterEdits += 1
        edit = (editedRange, delta)
      }
    }
    init(_ parent: RichTextEditor) {
      self.parent = parent
      lastDocument = parent.document
    }
    func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      let previous = (textView.string as NSString).substring(with: affectedCharRange)
      changesParagraphs =
        changesParagraphs || previous.contains("\n") || previous.contains("\r")
        || replacementString?.contains("\n") == true || replacementString?.contains("\r") == true
      return true
    }
    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView, !view.hasMarkedText(),
        let storage = view.textStorage
      else { return }
      let value = projection.update(
        storage, editedRange: characterEdits == 1 ? edit?.range : nil,
        changeInLength: edit?.delta ?? 0)
      characterEdits = 0
      edit = nil
      changesParagraphs = false
      lastDocument = value
      parent.document = value
      parent.text = value.plainText
      parent.controller.updateSelection()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      parent.controller.updateSelection()
    }
  }
}

final class RichComposerTextView: PlaceholderTextView {
  weak var controller: RichTextController?
  var onLink: (() -> Void)?
  private var normalizingMarkers = false
  override func didChangeText() {
    if !normalizingMarkers, !hasMarkedText(), let storage = textStorage {
      let coordinator = delegate as? RichTextEditor.Coordinator
      if undoManager?.isUndoing != true && undoManager?.isRedoing != true,
        coordinator?.changesParagraphs != false
      {
        normalizeNumbering(storage)
      }
      RichTextListLayout.normalize(storage, range: coordinator?.editedRangeForLayout)
    }
    super.didChangeText()
  }
  private func normalizeNumbering(_ storage: NSTextStorage) {
    let source = storage.string as NSString
    var location = 0
    var ordinal = 0
    var edits: [(NSRange, String)] = []
    while location < source.length {
      let range = source.paragraphRange(for: NSRange(location: location, length: 0))
      let kind =
        storage.attribute(RichTextCodec.listKind, at: location, effectiveRange: nil) as? String
        ?? "paragraph"
      ordinal = kind == "numbered" ? ordinal + 1 : 0
      if kind == "numbered" {
        let line = source.substring(with: range)
        let prefix = RichTextListLayout.prefixLength(in: line, kind: kind)
        let marker = "\(ordinal). "
        if prefix > 0 && !line.hasPrefix(marker) {
          edits.append((NSRange(location: location, length: prefix), marker))
        }
      }
      location = NSMaxRange(range)
    }
    guard !edits.isEmpty else { return }
    let before = NSAttributedString(attributedString: storage)
    normalizingMarkers = true
    defer { normalizingMarkers = false }
    let selection = selectedRange()
    for (range, marker) in edits.reversed() {
      if shouldChangeText(in: range, replacementString: marker) {
        storage.replaceCharacters(in: range, with: marker)
      }
    }
    setSelectedRange(RichTextSelection.map(selection, from: before, to: storage))
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
      if event.charactersIgnoringModifiers == "b" {
        controller?.toggleBold()
        return
      }
      if event.charactersIgnoringModifiers == "k" {
        onLink?()
        return
      }
    }
    super.keyDown(with: event)
  }
  override func insertNewline(_ sender: Any?) {
    guard isEditable, !hasMarkedText(), let storage = textStorage else {
      super.insertNewline(sender)
      return
    }
    let range = (string as NSString).paragraphRange(for: selectedRange())
    let line = (string as NSString).substring(with: range).trimmingCharacters(in: .newlines)
    let kind =
      range.location < storage.length
      ? storage.attribute(RichTextCodec.listKind, at: range.location, effectiveRange: nil)
        as? String : nil
    guard ["bullet", "numbered"].contains(kind ?? "") else {
      super.insertNewline(sender)
      return
    }
    if line == "• " || line.range(of: #"^\d+\. $"#, options: .regularExpression) != nil {
      controller?.toggleList(kind!)
      return
    }
    super.insertNewline(sender)
    let ordinal = Int(line.prefix(while: { $0.isNumber })) ?? 0
    insertText(kind == "bullet" ? "• " : "\(ordinal + 1). ", replacementRange: selectedRange())
  }
  override func paste(_ sender: Any?) {
    guard isEditable else { return }
    if onPaste?(.general) == true { return }
    // Paste prose as text; file/image paste continues through the attachment path.
    // Formatting is authored here rather than importing arbitrary HTML resources.
    pasteAsPlainText(sender)
  }
}
