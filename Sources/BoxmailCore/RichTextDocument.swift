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
    let text = NSMutableAttributedString(attributedString: input)
    let lineEndings = try! NSRegularExpression(pattern: "\r\n?")
    for match in lineEndings.matches(
      in: text.string, range: NSRange(location: 0, length: text.length)
    ).reversed() {
      text.replaceCharacters(in: match.range, with: "\n")
    }
    let source = text.string as NSString
    var blocks: [RichTextBlock] = []
    var location = 0
    while location <= source.length {
      let newline = source.range(
        of: "\n", range: NSRange(location: location, length: source.length - location))
      let end = newline.location == NSNotFound ? source.length : newline.location
      let paragraphRange = NSRange(location: location, length: end - location)
      let kind =
        location < text.length
        ? text.attribute(listKind, at: location, effectiveRange: nil) as? String ?? "paragraph"
        : "paragraph"
      let content = source.substring(with: paragraphRange)
      let prefixLength = RichTextListLayout.prefixLength(in: content, kind: kind)
      var runs: [RichTextRun] = []
      let range = NSRange(
        location: location + prefixLength, length: paragraphRange.length - prefixLength)
      text.enumerateAttributes(in: range) { attributes, range, _ in
        let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
        let run = RichTextRun(
          text: source.substring(with: range), bold: traits.contains(.bold),
          italic: traits.contains(.italic),
          link: link.flatMap { RichTextDocument.safeLink($0)?.absoluteString },
          fontSize: (attributes[.font] as? NSFont).map { Double($0.pointSize) },
          color: (attributes[.foregroundColor] as? NSColor).flatMap(RichTextStyle.hexColor))
        if let last = runs.last,
          last.bold == run.bold && last.italic == run.italic && last.link == run.link
            && last.fontSize == run.fontSize && last.color == run.color
        {
          runs[runs.count - 1].text += run.text
        } else {
          runs.append(run)
        }
      }
      blocks.append(
        .init(kind: ["bullet", "numbered"].contains(kind) ? kind : "paragraph", runs: runs))
      if newline.location == NSNotFound { break }
      location = end + 1
    }
    return RichTextDocument(blocks: blocks)
  }
}
