import AppKit
import UniformTypeIdentifiers

enum ComposerAttachmentSource {
  case file(URL)
  case image(Data)

  struct Payload {
    let name: String
    let contentType: String
    let data: Data
  }

  static func read(from pasteboard: NSPasteboard) throws -> [Self] {
    let urls = pasteboard.readObjects(forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    if !urls.isEmpty { return urls.map { .file($0) } }
    if let png = pasteboard.data(forType: .png) { return [.image(png)] }
    if let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) { return [.image(png)] }
    return []
  }

  func payload() throws -> Payload {
    let limit = 25 * 1024 * 1024
    switch self {
    case .file(let url):
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
      guard values.isRegularFile == true else { throw failure("请选择文件，文件夹不能直接作为附件。") }
      guard (values.fileSize ?? 0) <= limit else { throw failure("\(url.lastPathComponent)：单个附件不能超过 25 MB") }
      let data = try Data(contentsOf: url)
      guard data.count <= limit else { throw failure("\(url.lastPathComponent)：单个附件不能超过 25 MB") }
      return Payload(name: url.lastPathComponent,
        contentType: values.contentType?.preferredMIMEType ?? "application/octet-stream", data: data)
    case .image(let data):
      guard data.count <= limit else { throw failure("单张图片不能超过 25 MB") }
      let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
      return Payload(name: "粘贴图片-\(stamp).png", contentType: "image/png", data: data)
    }
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "BoxmailAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
