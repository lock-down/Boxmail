import AppKit
import UniformTypeIdentifiers

@MainActor enum DiagnosticExportService {
  static func chooseDestination() async -> URL? {
    let panel = NSSavePanel()
    panel.title = "导出 Boxmail 诊断日志"
    panel.allowedContentTypes = [.zip]
    let date = DateFormatter()
    date.dateFormat = "yyyy-MM-dd-HHmmss"
    panel.nameFieldStringValue = "Boxmail-Diagnostics-\(date.string(from: Date())).zip"
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
