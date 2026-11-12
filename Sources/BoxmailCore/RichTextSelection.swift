import Foundation

/// Preserve content positions when presentation-only list prefixes change.
public enum RichTextSelection {
  public static func map(
    _ selection: NSRange, from old: NSAttributedString, to new: NSAttributedString
  ) -> NSRange {
    let before = paragraphs(old)
    let after = paragraphs(new)
    func position(_ value: Int) -> Int {
      for (index, line) in before.enumerated() where index < after.count {
        if value <= line.start + line.length || index == before.count - 1 {
          let target = after[index]
          let contentOffset = max(0, value - line.start - line.prefix)
          return target.start + target.prefix
            + min(contentOffset, max(0, target.length - target.prefix))
        }
      }
      return new.length
    }
    let start = position(selection.location)
    let end = position(NSMaxRange(selection))
    return NSRange(location: start, length: max(0, end - start))
  }
  private static func paragraphs(_ value: NSAttributedString) -> [(
    start: Int, length: Int, prefix: Int
  )] {
    let lines = value.string.components(separatedBy: "\n")
    var offset = 0
    return lines.map { line in
      let kind =
        offset < value.length
        ? value.attribute(RichTextCodec.listKind, at: offset, effectiveRange: nil) as? String
          ?? "paragraph" : "paragraph"
      defer { offset += line.utf16.count + 1 }
      return (offset, line.utf16.count, RichTextListLayout.prefixLength(in: line, kind: kind))
    }
  }
}
