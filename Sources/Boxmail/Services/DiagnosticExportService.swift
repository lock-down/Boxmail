import AppKit
import UniformTypeIdentifiers

@MainActor enum DiagnosticExportService {
  static func chooseDestination() async -> URL? {
    let panel = FilePanel.savePanel(
      title: "导出 Boxmail 诊断日志",
      name: "Boxmail-Diagnostics-\(FilePanel.fileStamp("yyyy-MM-dd-HHmmss")).zip", types: [.zip])
    let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
      if let window = NSApp.keyWindow {
        panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
      } else {
        panel.begin { continuation.resume(returning: $0) }
      }
    }
    return response == .OK ? panel.url : nil
  }
}
