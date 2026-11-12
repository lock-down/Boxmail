import AppKit

enum MainWindowLayout {
  static let defaultSize = NSSize(width: 1440, height: 900)
  static let minimumSize = NSSize(width: 720, height: 600)

  /// A restored window must remain visibly smaller even when the default size fills a small display.
  static func defaultRestoreFrame(for window: NSWindow, within screen: NSRect) -> NSRect {
    let preferred = window.frameRect(forContentRect: NSRect(origin: .zero, size: defaultSize)).size
    let minimumContent = NSSize(
      width: max(minimumSize.width, window.contentMinSize.width),
      height: max(minimumSize.height, window.contentMinSize.height))
    let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContent)).size
    let width = min(
      screen.width, max(minimum.width, min(preferred.width, floor(screen.width * 0.85))))
    let height = min(
      screen.height, max(minimum.height, min(preferred.height, floor(screen.height * 0.85))))
    return NSRect(
      x: floor(screen.midX - width / 2), y: floor(screen.midY - height / 2), width: width,
      height: height)
  }
}
