import AppKit
import UniformTypeIdentifiers

@MainActor enum FilePanel {
  static func fileStamp(_ format: String = "yyyy-MM-dd") -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: .now)
  }

  static func savePanel(title: String, name: String, types: [UTType]? = nil) -> NSSavePanel {
    let panel = NSSavePanel()
    panel.title = title
    if let types { panel.allowedContentTypes = types }
    panel.nameFieldStringValue = name
    return panel
  }

  static func save(title: String, name: String, types: [UTType]? = nil) -> URL? {
    let panel = savePanel(title: title, name: name, types: types)
    return panel.runModal() == .OK ? panel.url : nil
  }

  static func openURLs(
    title: String = "", types: [UTType]? = nil, canChooseFiles: Bool = true,
    canChooseDirectories: Bool = false, allowsMultipleSelection: Bool = false,
    canCreateDirectories: Bool = false, directory: URL? = nil,
    message: String? = nil, prompt: String? = nil
  ) -> [URL]? {
    let panel = NSOpenPanel()
    panel.title = title
    if let types { panel.allowedContentTypes = types }
    panel.canChooseFiles = canChooseFiles
    panel.canChooseDirectories = canChooseDirectories
    panel.allowsMultipleSelection = allowsMultipleSelection
    panel.canCreateDirectories = canCreateDirectories
    if let directory { panel.directoryURL = directory }
    if let message { panel.message = message }
    if let prompt { panel.prompt = prompt }
    return panel.runModal() == .OK ? panel.urls : nil
  }

  static func open(
    title: String = "", types: [UTType]? = nil, canChooseFiles: Bool = true,
    canChooseDirectories: Bool = false, canCreateDirectories: Bool = false,
    directory: URL? = nil, message: String? = nil, prompt: String? = nil
  ) -> URL? {
    openURLs(
      title: title, types: types, canChooseFiles: canChooseFiles,
      canChooseDirectories: canChooseDirectories, allowsMultipleSelection: false,
      canCreateDirectories: canCreateDirectories, directory: directory, message: message,
      prompt: prompt)?.first
  }
}
