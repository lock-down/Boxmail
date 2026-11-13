import SwiftUI

/// Sheet content fits its presenting surface; nested sheets inherit the resolved size.
struct WorkspaceSheetLayout {
  let preferred: CGSize
  let minimum: CGSize

  func size(in available: CGSize) -> CGSize {
    CGSize(
      width: min(preferred.width, max(minimum.width, available.width - 24)),
      height: min(preferred.height, max(minimum.height, available.height - 40)))
  }

  static let settings = Self(preferred: CGSize(width: 1000, height: 750), minimum: CGSize(width: 700, height: 500))
  static let composer = Self(preferred: CGSize(width: 1080, height: 720), minimum: CGSize(width: 680, height: 500))
  static let attachment = Self(preferred: CGSize(width: 1080, height: 720), minimum: CGSize(width: 640, height: 480))
  static let categories = Self(preferred: CGSize(width: 760, height: 520), minimum: CGSize(width: 640, height: 480))
  static let provider = Self(preferred: CGSize(width: 680, height: 720), minimum: CGSize(width: 640, height: 480))
}

private struct WorkspaceViewportKey: EnvironmentKey {
  static let defaultValue = MainWindowLayout.defaultSize
}

extension EnvironmentValues {
  var workspaceViewport: CGSize {
    get { self[WorkspaceViewportKey.self] }
    set { self[WorkspaceViewportKey.self] = newValue }
  }
}

private struct WorkspaceSheetSize: ViewModifier {
  let layout: WorkspaceSheetLayout
  @Environment(\.workspaceViewport) private var viewport

  func body(content: Content) -> some View {
    let size = layout.size(in: viewport)
    content.frame(width: size.width, height: size.height)
      .environment(\.workspaceViewport, size)
  }
}

extension View {
  func workspaceSheet(_ layout: WorkspaceSheetLayout) -> some View {
    modifier(WorkspaceSheetSize(layout: layout))
  }
}
