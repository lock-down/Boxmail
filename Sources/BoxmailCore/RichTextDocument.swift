import AppKit
import Foundation

public struct RichTextRun: Codable, Hashable {
  public var text: String
  public var bold = false
  public var italic = false
  public var link: String?
  public var fontSize: Double?
  public var color: String?
  public init(
    text: String, bold: Bool = false, italic: Bool = false, link: String? = nil,
    fontSize: Double? = nil, color: String? = nil
  ) {
    self.text = text
    self.bold = bold
    self.italic = italic
    self.link = link
    self.fontSize = RichTextStyle.normalizedFontSize(fontSize)
    self.color = RichTextStyle.normalizedColor(color)
  }
}

public struct RichTextBlock: Codable, Hashable {
  public var kind: String
  public var runs: [RichTextRun]
  public init(kind: String = "paragraph", runs: [RichTextRun]) {
    self.kind = kind
    self.runs = runs
  }
}

public struct RichTextDocument: Codable, Hashable {
  public var blocks: [RichTextBlock]
  public init(blocks: [RichTextBlock]) { self.blocks = blocks }
  public init(text: String) {
    blocks = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n"
    )
    .components(separatedBy: "\n").map {
      RichTextBlock(runs: $0.isEmpty ? [] : [.init(text: $0)])
    }
  }
  public var plainText: String {
    var ordinal = 0
    return blocks.map { block in
      if block.kind == "numbered" { ordinal += 1 } else { ordinal = 0 }
      return (block.kind == "bullet" ? "• " : block.kind == "numbered" ? "\(ordinal). " : "")
        + block.runs.map(\.text).joined()
    }.joined(separator: "\n")
  }
  public static func safeLink(_ value: String) -> URL? {
    guard value.count <= 4000,
      !value.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }),
      let url = URL(string: value),
      ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    else { return nil }
    return url
  }
}

/// Semantic text crosses the persistence boundary; layout-only signature spacing does not.
public enum RichTextCodec {
  private static let lineEndings = try! NSRegularExpression(pattern: "\r\n?")
  public static let listKind = NSAttributedString.Key("BoxmailListKind")

  public static func attributed(
    _ document: RichTextDocument, fontSize: CGFloat = CGFloat(RichTextStyle.defaultFontSize)
  )
    -> NSAttributedString
  {
    let result = NSMutableAttributedString()
    var ordinal = 0
    var previousAttributes: [NSAttributedString.Key: Any] = [:]
    for (index, block) in document.blocks.enumerated() {
      if block.kind == "numbered" { ordinal += 1 } else { ordinal = 0 }
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = 5
      let prefix = block.kind == "bullet" ? "• " : block.kind == "numbered" ? "\(ordinal). " : ""
      let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize),
        .foregroundColor: RichTextStyle.nsColor(nil),
        .paragraphStyle: paragraph, listKind: block.kind,
      ]
      if index > 0 {
        result.append(NSAttributedString(string: "\n", attributes: previousAttributes))
      }
      var markerAttributes = base
      if block.runs.isEmpty {
        markerAttributes[.font] = previousAttributes[.font] ?? base[.font]
        markerAttributes[.foregroundColor] =
          previousAttributes[.foregroundColor] ?? base[.foregroundColor]
      }
      result.append(NSAttributedString(string: prefix, attributes: markerAttributes))
      previousAttributes = markerAttributes
      for run in block.runs {
        var attributes = base
        var font = NSFont.systemFont(
          ofSize: RichTextStyle.normalizedFontSize(run.fontSize).map { CGFloat($0) } ?? fontSize,
          weight: run.bold ? .bold : .regular)
        if run.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        attributes[.font] = font
        attributes[.foregroundColor] = RichTextStyle.nsColor(run.color)
        if let link = run.link.flatMap(RichTextDocument.safeLink) { attributes[.link] = link }
        result.append(NSAttributedString(string: run.text, attributes: attributes))
        previousAttributes = attributes
      }
    }
    RichTextListLayout.normalize(result)
    return result
  }

  public static func document(_ input: NSAttributedString) -> RichTextDocument {
    let text: NSAttributedString
    if input.string.contains("\r") {
      let normalized = NSMutableAttributedString(attributedString: input)
      for match in lineEndings.matches(
        in: input.string, range: NSRange(location: 0, length: input.length)
      ).reversed() {
        normalized.replaceCharacters(in: match.range, with: "\n")
      }
      text = normalized
    } else {
      text = input
    }
    let source = text.string as NSString
    struct StyleKey: Equatable {
      let font: ObjectIdentifier?
      let color: ObjectIdentifier?
      let link: String?
    }
    var previousStyleKey: StyleKey?
    var previousStyle: RichTextRun?
    var blocks: [RichTextBlock] = []
    var contentRanges: [NSRange] = []
    var location = 0
    while location <= source.length {
      let newline = source.range(
        of: "\n", range: NSRange(location: location, length: source.length - location))
      let end = newline.location == NSNotFound ? source.length : newline.location
      let kind =
        location < text.length
        ? text.attribute(listKind, at: location, effectiveRange: nil) as? String ?? "paragraph"
        : "paragraph"
      let content = source.substring(with: NSRange(location: location, length: end - location))
      let prefix = RichTextListLayout.prefixLength(in: content, kind: kind)
      contentRanges.append(NSRange(location: location + prefix, length: end - location - prefix))
      blocks.append(
        .init(kind: ["bullet", "numbered"].contains(kind) ? kind : "paragraph", runs: []))
      if newline.location == NSNotFound { break }
      location = end + 1
    }
    // Enumerate style spans once. One span can cover thousands of paragraphs;
    // opening a Foundation attribute enumerator for every paragraph is avoidable.
    var paragraph = 0
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, span, _ in
      let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
      let font = attributes[.font] as? NSFont
      let color = attributes[.foregroundColor] as? NSColor
      let key = StyleKey(
        font: font.map(ObjectIdentifier.init), color: color.map(ObjectIdentifier.init), link: link)
      var style: RichTextRun
      if key == previousStyleKey, let cached = previousStyle {
        style = cached
      } else {
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        style = RichTextRun(
          text: "", bold: traits.contains(.bold), italic: traits.contains(.italic),
          link: link.flatMap { RichTextDocument.safeLink($0)?.absoluteString },
          fontSize: font.map { Double($0.pointSize) }, color: color.flatMap(RichTextStyle.hexColor))
        previousStyleKey = key
        previousStyle = style
      }
      while paragraph < contentRanges.count {
        let content = contentRanges[paragraph]
        if NSMaxRange(content) <= span.location {
          paragraph += 1
          continue
        }
        if content.location >= NSMaxRange(span) { break }
        let range = NSIntersectionRange(content, span)
        if range.length > 0 {
          var run = style
          run.text = source.substring(with: range)
          if let last = blocks[paragraph].runs.last,
            last.bold == run.bold && last.italic == run.italic && last.link == run.link
              && last.fontSize == run.fontSize && last.color == run.color
          {
            blocks[paragraph].runs[blocks[paragraph].runs.count - 1].text += run.text
          } else {
            blocks[paragraph].runs.append(run)
          }
        }
        if NSMaxRange(content) <= NSMaxRange(span) { paragraph += 1 } else { break }
      }
    }
    return RichTextDocument(blocks: blocks)
  }
}
