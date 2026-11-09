import AppKit
import Foundation

/// List markers are presentation derived from the first content character, never saved as runs.
public enum RichTextListLayout {
  public static func prefixLength(in content: String, kind: String) -> Int {
    if kind == "bullet", content.hasPrefix("• ") { return 2 }
    if kind == "numbered", let range = content.range(of: #"^\d+\. "#, options: .regularExpression) {
      return content[range].utf16.count
    }
    return 0
  }

  public static func normalize(_ text: NSMutableAttributedString) {
    let source = text.string as NSString
    var location = 0
    var previousAttributes: [NSAttributedString.Key: Any] = [:]
    text.beginEditing()
    defer { text.endEditing() }
    while location < source.length {
      let range = source.paragraphRange(for: NSRange(location: location, length: 0))
      let line = source.substring(with: range).trimmingCharacters(in: .newlines)
      defer {
        previousAttributes = text.attributes(
          at: location + max(0, line.utf16.count - 1), effectiveRange: nil)
        location = NSMaxRange(range)
      }
      let kind =
        text.attribute(RichTextCodec.listKind, at: location, effectiveRange: nil) as? String
        ?? "paragraph"
      let length = prefixLength(in: line, kind: kind)
      guard length > 0 else { continue }
      let marker = NSRange(location: location, length: length)
      let attributes =
        line.utf16.count > length
        ? text.attributes(at: location + length, effectiveRange: nil)
        : previousAttributes.isEmpty
          ? text.attributes(at: location, effectiveRange: nil) : previousAttributes
      let fontSize =
        (attributes[.font] as? NSFont)?.pointSize
        ?? CGFloat(RichTextStyle.defaultFontSize)
      let font = NSFont.systemFont(ofSize: fontSize)
      let color =
        attributes[.foregroundColor] as? NSColor
        ?? RichTextStyle.nsColor(nil)
      text.addAttributes([.font: font, .foregroundColor: color], range: marker)
      text.removeAttribute(.link, range: marker)
      text.removeAttribute(.underlineStyle, range: marker)
      let paragraph =
        (text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
        .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
      paragraph.firstLineHeadIndent = 0
      paragraph.headIndent = ceil(
        (source.substring(with: marker) as NSString).size(withAttributes: [.font: font]).width)
      text.addAttribute(.paragraphStyle, value: paragraph, range: range)
    }
  }
}
