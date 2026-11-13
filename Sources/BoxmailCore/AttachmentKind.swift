import Foundation

public enum AttachmentKind {
  case pdf, word, spreadsheet, presentation, image, text, archive, other

  // The same JSON table is read by the local service; adding a format updates
  // both previews and analysis without a second hand-maintained switch.
  private static let table: (extensions: [String: AttachmentKind], mimes: [String: AttachmentKind]) = {
    guard let url = Bundle.module.url(forResource: "AttachmentKinds", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let formats = root["formats"] as? [[String: Any]]
    else { preconditionFailure("Boxmail attachment kind resource is missing") }
    var extensions: [String: AttachmentKind] = [:]
    var mimes: [String: AttachmentKind] = [:]
    for format in formats {
      guard let name = format["kind"] as? String, let kind = AttachmentKind(wireName: name) else {
        continue
      }
      for extensionName in format["extensions"] as? [String] ?? [] { extensions[extensionName] = kind }
      for mime in format["mimes"] as? [String] ?? [] { mimes[mime] = kind }
    }
    return (extensions, mimes)
  }()

  private init?(wireName: String) {
    switch wireName {
    case "pdf": self = .pdf
    case "word": self = .word
    case "spreadsheet": self = .spreadsheet
    case "presentation": self = .presentation
    case "image": self = .image
    case "text": self = .text
    case "archive": self = .archive
    default: return nil
    }
  }

  public init(name: String, contentType: String) {
    if let kind = Self.table.extensions[(name as NSString).pathExtension.lowercased()] {
      self = kind
      return
    }
    let mime = contentType.split(separator: ";", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    self = Self.table.mimes[mime] ?? .other
  }
}
