import Foundation
import BoxmailCore

/// Keep the system's Office rendering and local image assets, while owning the
/// surrounding page and scrollbar layout instead of embedding Quick Look's remote UI.
@MainActor enum SystemDocumentPreview {
  static func prepare(_ file: AttachmentPreviewFile) async throws -> URL? {
    let output = file.directory.appendingPathComponent("DocumentPreview", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    process.arguments = ["-p", "-o", output.path, file.url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let timeout = Task {
      try await Task.sleep(for: .seconds(30))
      if process.isRunning { process.terminate() }
    }
    defer { timeout.cancel() }
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        process.terminationHandler = { process in
          if process.terminationStatus == 0 { continuation.resume() }
          else { continuation.resume(throwing: failure()) }
        }
        do { try process.run() }
        catch { continuation.resume(throwing: error) }
      }
      try Task.checkCancellation()
    } onCancel: {
      Task { @MainActor in if process.isRunning { process.terminate() } }
    }
    let previews = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
    guard let folder = previews.first(where: { $0.pathExtension == "qlpreview" }) else { return nil }
    let url = folder.appendingPathComponent("Preview.html")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let html = try String(contentsOf: url, encoding: .utf8)
    guard let head = html.range(of: "<head>", options: .caseInsensitive) else { throw failure() }
    var styled = html
    styled.insert(contentsOf: chrome, at: head.upperBound)
    try styled.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private nonisolated static func failure() -> NSError {
    NSError(domain: "BoxmailDocumentPreview", code: 1, userInfo: [NSLocalizedDescriptionKey:
      "系统未能生成文档预览，请重试或使用“打开原文件”查看。"])
  }

  private static let chrome = """
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data:; style-src 'unsafe-inline'; font-src file: data:; base-uri 'none'; form-action 'none'">
    <style id="boxmail-preview-chrome">
    html { min-height: 100%; background: white; }
    body { display: flow-root; min-width: fit-content; margin: 0 !important; padding: 24px !important; box-sizing: border-box; }
    body > div { margin-left: auto !important; margin-right: auto !important; }
    html, body { border: 0 !important; outline: none !important; box-shadow: none !important; }
    ::selection { background: #eaf1fb; }
    ::-webkit-scrollbar { width: 6px; height: 6px; background: transparent; }
    ::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; border: 0; box-shadow: none; }
    ::-webkit-scrollbar-thumb { background: rgba(32,36,43,.3); border: 0; border-radius: 3px; box-shadow: none; }
    </style>
    """
}
