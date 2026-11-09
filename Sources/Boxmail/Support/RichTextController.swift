import AppKit
import BoxmailCore
import Observation

@Observable @MainActor final class RichTextController {
  @ObservationIgnored weak var textView: RichComposerTextView?
  var bold = false
  var list = "paragraph"
  var fontSize: Double? = RichTextStyle.defaultFontSize
  var color: String?
  var hasMixedColor = false

  func updateSelection() {
    guard let view = textView else { return }
    var styles: [[NSAttributedString.Key: Any]] = []
    let range = view.selectedRange()
    if range.length > 0, let storage = view.textStorage, NSMaxRange(range) <= storage.length {
      storage.enumerateAttributes(in: range) { attributes, _, _ in styles.append(attributes) }
    } else {
      styles = [view.typingAttributes]
    }
    bold = styles.allSatisfy {
      ($0[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
    }
    list = styles.first?[RichTextCodec.listKind] as? String ?? "paragraph"
    let sizes = Set(
      styles.map {
        RichTextStyle.normalizedFontSize(($0[.font] as? NSFont).map { Double($0.pointSize) })
          ?? RichTextStyle.defaultFontSize
      })
    fontSize = sizes.count == 1 ? sizes.first : nil
    let colors = Set(
      styles.map { ($0[.foregroundColor] as? NSColor).flatMap(RichTextStyle.hexColor) })
    hasMixedColor = colors.count > 1
    color = hasMixedColor ? nil : colors.first ?? nil
  }

  func toggleBold() {
    let removeBold = bold
    changeInlineStyle(name: "粗体") { attributes in
      let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: RichTextStyle.defaultFontSize)
      attributes[.font] = NSFontManager.shared.convert(
        font, toHaveTrait: removeBold ? .unboldFontMask : .boldFontMask)
    }
  }

  func setFontSize(_ size: Double) {
    guard size.isFinite, RichTextStyle.fontSizeRange.contains(size) else { return }
    let pointSize = RichTextStyle.normalizedFontSize(size) ?? RichTextStyle.defaultFontSize
    changeInlineStyle(name: "字号") { attributes in
      let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: RichTextStyle.defaultFontSize)
      attributes[.font] = NSFontManager.shared.convert(font, toSize: pointSize)
    }
  }

  func setColor(_ value: String?) {
    guard
      value == nil || value?.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
    else { return }
    changeInlineStyle(name: "文字颜色") { attributes in
      attributes[.foregroundColor] = RichTextStyle.nsColor(value)
    }
  }

  private func changeInlineStyle(
    name: String, transform: (inout [NSAttributedString.Key: Any]) -> Void
  ) {
    guard let view = textView, view.isEditable, !view.hasMarkedText(),
      let storage = view.textStorage
    else { return }
    view.window?.makeFirstResponder(view)
    let selection = view.selectedRange()
    if selection.length == 0 {
      var attributes = view.typingAttributes
      transform(&attributes)
      view.typingAttributes = attributes
      updateSelection()
    } else {
      let value = NSMutableAttributedString(attributedString: storage)
      storage.enumerateAttributes(in: selection) { attributes, range, _ in
        var attributes = attributes
        transform(&attributes)
        value.setAttributes(attributes, range: range)
      }
      replace(value, selection: selection, name: name, affectedRange: selection)
    }
  }

  func toggleList(_ kind: String) {
    guard let view = textView, view.isEditable, !view.hasMarkedText(),
      let storage = view.textStorage
    else { return }
    let selection = view.selectedRange()
    let source = view.string as NSString
    let range = source.paragraphRange(for: selection)
    let before = source.substring(to: range.location).filter { $0 == "\n" }.count
    let count = max(
      1,
      source.substring(with: range).split(separator: "\n", omittingEmptySubsequences: false).count
        - (NSMaxRange(range) < source.length || source.substring(with: range).hasSuffix("\n")
          ? 1 : 0))
    var document = RichTextCodec.document(storage)
    for index in before..<min(document.blocks.count, before + count) {
      document.blocks[index].kind = list == kind ? "paragraph" : kind
    }
    replace(RichTextCodec.attributed(document), selection: selection, name: "列表")
  }

  @discardableResult func applyLink(_ value: String) -> Bool {
    guard let link = RichTextDocument.safeLink(value), let view = textView, view.isEditable,
      !view.hasMarkedText(), let storage = view.textStorage
    else { return false }
    let selection = view.selectedRange()
    var range = selection
    let result = NSMutableAttributedString(attributedString: storage)
    if range.length == 0 {
      let inserted = NSAttributedString(string: value, attributes: view.typingAttributes)
      result.insert(inserted, at: range.location)
      range.length = inserted.length
    }
    result.addAttribute(.link, value: link, range: range)
    replace(result, selection: range, name: "添加链接", affectedRange: selection)
    return true
  }

  private func replace(
    _ value: NSAttributedString, selection: NSRange, name: String, affectedRange: NSRange? = nil
  ) {
    guard let view = textView, view.isEditable, let storage = view.textStorage else { return }
    view.breakUndoCoalescing()
    let range = affectedRange ?? NSRange(location: 0, length: storage.length)
    let replacement =
      value.string == storage.string
      ? nil
      : value.attributedSubstring(
        from: NSRange(
          location: range.location, length: value.length - storage.length + range.length)
      ).string
    guard
      view.shouldChangeText(
        in: range, replacementString: replacement)
    else { return }
    // TextKit owns the attributed undo record for precisely the affected range.
    storage.setAttributedString(value)
    let location = min(selection.location, storage.length)
    view.setSelectedRange(
      NSRange(location: location, length: min(selection.length, storage.length - location)))
    view.didChangeText()
    view.undoManager?.setActionName(name)
    view.window?.makeFirstResponder(view)
    updateSelection()
  }
}
