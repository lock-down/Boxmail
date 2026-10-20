import Foundation

public enum AttachmentKind {
  case pdf, word, spreadsheet, presentation, image, text, other

  public init(name: String, contentType: String) {
    switch (name as NSString).pathExtension.lowercased() {
    case "pdf": self = .pdf
    case "doc", "docx", "odt", "rtf": self = .word
    case "xls", "xlsx", "csv", "ods": self = .spreadsheet
    case "ppt", "pptx", "pps", "ppsx": self = .presentation
    case "jpg", "jpeg", "png", "gif", "webp": self = .image
    case "txt", "md", "json", "log": self = .text
    default:
      let mime = contentType.split(separator: ";", maxSplits: 1).first?
        .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
      switch mime {
      case "application/pdf": self = .pdf
      case "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": self = .word
      case "application/vnd.ms-excel", "text/csv",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": self = .spreadsheet
      case "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow": self = .presentation
      case "image/jpeg", "image/png", "image/gif", "image/webp": self = .image
      case "text/plain", "text/markdown", "application/json": self = .text
      default: self = .other
      }
    }
  }
}
