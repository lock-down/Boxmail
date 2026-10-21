import AppKit
import SwiftUI

extension View {
  func borderlessScrollers() -> some View {
    background(ScrollAppearanceScope().frame(width: 0, height: 0)
      .allowsHitTesting(false).accessibilityHidden(true))
  }
}

/// Covers native scroll views created later by WebKit, PDFKit, and Quick Look, too.
private struct ScrollAppearanceScope: NSViewRepresentable {
  func makeNSView(context: Context) -> ScopeView { ScopeView() }
  func updateNSView(_ nsView: ScopeView, context: Context) { nsView.scheduleRefresh() }
  static func dismantleNSView(_ nsView: ScopeView, coordinator: ()) { nsView.stopObserving() }

  final class ScopeView: NSView {
    private var observers: [NSObjectProtocol] = []
    private var refreshPending = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopObserving()
      guard let window else { return }
      for (name, object) in [(NSWindow.didUpdateNotification, window as AnyObject?),
        (NSScroller.preferredScrollerStyleDidChangeNotification, nil)] {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object,
          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
          })
      }
      scheduleRefresh()
    }

    override func layout() {
      super.layout()
      scheduleRefresh()
    }

    func scheduleRefresh() {
      guard window != nil, !refreshPending else { return }
      refreshPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.refreshPending = false
        if let root = self.window?.contentView { ScrollAppearance.applyRecursively(to: root) }
      }
    }

    func stopObserving() {
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers.removeAll()
    }
  }
}
