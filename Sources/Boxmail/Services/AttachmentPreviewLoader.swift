import BoxmailCore
import Foundation
import PDFKit

/// Decode and validate files away from the UI actor; the caller owns the returned directory.
enum AttachmentPreviewLoader {
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
