import BoxmailCore
import Foundation
import PDFKit

struct LoadedAttachmentPreview {
  let file: AttachmentPreviewFile
  let documentURL: URL?
}

/// Decode and validate files away from the UI actor; the caller owns the returned directory.
enum AttachmentPreviewLoader {
  @MainActor static func load(
    path: String, isPDF: Bool, isWord: Bool
  ) async throws -> LoadedAttachmentPreview {
    let response: FileResponse = try await BackendService.shared.request(path)
    try Task.checkCancellation()
    let file = try await prepare(name: response.name, content: response.content, isPDF: isPDF)
    var keep = false
    defer { if !keep { file.remove() } }
    var documentURL: URL?
    if isWord {
      documentURL = try await SystemDocumentPreview.prepare(file)
      try Task.checkCancellation()
    }
    try Task.checkCancellation()
    keep = true
    return LoadedAttachmentPreview(file: file, documentURL: documentURL)
  }

  nonisolated static func prepare(
    name: String, content: String, isPDF: Bool, root: URL = FileManager.default.temporaryDirectory
  ) async throws
    -> AttachmentPreviewFile
  {
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      guard let data = Data(base64Encoded: content) else {
        throw NSError(
          domain: "BoxmailPreview", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "原文件数据无效，请重新下载附件。"])
      }
      let file = try AttachmentPreviewFile(name: name, data: data, root: root)
      do {
        try Task.checkCancellation()
        if isPDF {
          guard let document = PDFDocument(url: file.url), !document.isLocked else {
            throw NSError(
              domain: "BoxmailPreview", code: 2,
              userInfo: [NSLocalizedDescriptionKey: "PDF 已加密或文件损坏，请在原应用中查看。"])
          }
        }
        return file
      } catch {
        file.remove()
        throw error
      }
    }
    let file = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
    do {
      try Task.checkCancellation()
      return file
    } catch {
      file.remove()
      throw error
    }
  }
}
