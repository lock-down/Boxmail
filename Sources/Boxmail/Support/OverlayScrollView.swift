import AppKit
import SwiftUI

/// Keep the native scroll view and gestures, without a permanent bordered scroller gutter.
struct OverlayScrollView<Content: View>: View {
  private let axes: Axis.Set
  private let showsIndicators: Bool
  private let persistentIndicators: Bool
  private let content: Content

  init(
    _ axes: Axis.Set = .vertical, showsIndicators: Bool = true, persistentIndicators: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    self.persistentIndicators = persistentIndicators
    self.content = content()
  }

  var body: some View {
    ScrollView(axes, showsIndicators: showsIndicators) {
      content.background(ScrollStyleAnchor(persistentIndicators: persistentIndicators)
        .allowsHitTesting(false).accessibilityHidden(true))
    }
  }
}

private struct ScrollStyleAnchor: NSViewRepresentable {
  let persistentIndicators: Bool
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ nsView: AnchorView, context: Context) {
    nsView.persistentIndicators = persistentIndicators
    nsView.refreshWhenAttached()
  }
  static func dismantleNSView(_ nsView: AnchorView, coordinator: ()) { nsView.stopObserving() }

  final class AnchorView: NSView {
    var persistentIndicators = false
    private weak var styledScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var refreshPending = false

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      refreshWhenAttached()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { stopObserving() } else { refreshWhenAttached() }
    }

    override func layout() {
      super.layout()
      applyAppearance()
    }

    func refreshWhenAttached() {
      guard !refreshPending else { return }
      refreshPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.refreshPending = false
        self.applyAppearance()
      }
    }

    func stopObserving() {
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
      boundsObserver = nil
      styledScrollView = nil
    }

    private func applyAppearance() {
      guard window != nil, let scrollView = enclosingScrollView else { return }
      if styledScrollView !== scrollView {
        stopObserving()
        styledScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.refreshWhenAttached() }
        }
      }
      ScrollAppearance.apply(to: scrollView, persistentIndicators: persistentIndicators)
    }
  }
}
