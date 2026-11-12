import Foundation

/// Keeps the persisted semantic document current without converting unaffected paragraphs on each keypress.
public final class RichTextDocumentProjection {
  private var document = RichTextDocument(blocks: [])
  private var paragraphs: [NSRange] = []
  private var length = 0

  public init() {}

  @discardableResult public func reset(_ input: NSAttributedString) -> RichTextDocument {
    document = RichTextCodec.document(input)
    paragraphs = Self.paragraphs(input.string)
    length = input.length
    return document
  }

  public func update(_ input: NSAttributedString, editedRange: NSRange?, changeInLength: Int = 0)
    -> RichTextDocument
  {
    guard let editedRange, !paragraphs.isEmpty, paragraphs.count == document.blocks.count,
      input.length == length + changeInLength, editedRange.location <= length,
      NSMaxRange(editedRange) <= input.length
    else { return reset(input) }
    let oldEnd = editedRange.location + max(0, editedRange.length - changeInLength)
    guard oldEnd <= length,
      let first = paragraphs.lastIndex(where: { $0.location <= editedRange.location }),
      let affectedLast = paragraphs.lastIndex(where: { $0.location <= oldEnd })
    else { return reset(input) }
    // Include the next paragraph so deletion of a separator and insertion of new
    // separators have an unambiguous boundary in both versions.
    let last = min(paragraphs.count - 1, affectedLast + 1)
    let start = paragraphs[first].location
    let boundary = NSMaxRange(paragraphs[last]) + changeInLength
    guard boundary >= start, boundary <= input.length else { return reset(input) }
    let fragment = input.attributedSubstring(
      from: NSRange(location: start, length: boundary - start))
    if fragment.string.contains("\r") { return reset(input) }
    var replacement = RichTextCodec.document(fragment)
    var ranges = Self.paragraphs(fragment.string)
    if fragment.string.hasSuffix("\n"), boundary < input.length || last < paragraphs.count - 1 {
      replacement.blocks.removeLast()
      ranges.removeLast()
    }
    document.blocks.replaceSubrange(first...last, with: replacement.blocks)
    for index in (last + 1)..<paragraphs.count { paragraphs[index].location += changeInLength }
    paragraphs.replaceSubrange(
      first...last, with: ranges.map { NSRange(location: start + $0.location, length: $0.length) })
    length = input.length
    return document
  }

  private static func paragraphs(_ text: String) -> [NSRange] {
    let source = text as NSString
    var ranges: [NSRange] = []
    var start = 0
    while start <= source.length {
      let newline = source.range(
        of: "\n", range: NSRange(location: start, length: source.length - start))
      let end = newline.location == NSNotFound ? source.length : newline.location + 1
      ranges.append(NSRange(location: start, length: end - start))
      if newline.location == NSNotFound { break }
      start = end
    }
    return ranges
  }
}
