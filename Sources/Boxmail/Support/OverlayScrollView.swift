import AppKit
import SwiftUI

/// Keep the native scroll view and gestures, without a permanent bordered scroller gutter.
struct OverlayScrollView<Content: View>: View {
  private let axes: Axis.Set
  private let showsIndicators: Bool
  private let persistentIndicators: Bool
  private let scrollPosition: ScrollPositionState?
  private let followsContent: Bool
  private let content: Content

  init(
    _ axes: Axis.Set = .vertical, showsIndicators: Bool = true, persistentIndicators: Bool = false,
    scrollPosition: ScrollPositionState? = nil, followsContent: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    self.persistentIndicators = persistentIndicators
    self.scrollPosition = scrollPosition
    self.followsContent = followsContent
    self.content = content()
  }

  var body: some View {
    ScrollView(axes, showsIndicators: showsIndicators) {
      content.background(ScrollStyleAnchor(persistentIndicators: persistentIndicators,
        scrollPosition: scrollPosition, followsContent: followsContent)
        .allowsHitTesting(false).accessibilityHidden(true))
    }
  }
}

private struct ScrollStyleAnchor: NSViewRepresentable {
  let persistentIndicators: Bool
  let scrollPosition: ScrollPositionState?
  let followsContent: Bool
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ nsView: AnchorView, context: Context) {
    nsView.persistentIndicators = persistentIndicators
    nsView.scrollPosition = scrollPosition
    nsView.followsContent = followsContent
    nsView.refreshWhenAttached()
  }
  static func dismantleNSView(_ nsView: AnchorView, coordinator: ()) { nsView.stopObserving() }

  final class AnchorView: NSView {
    var persistentIndicators = false
    var scrollPosition: ScrollPositionState?
    var followsContent = false
    private weak var styledScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var documentObserver: NSObjectProtocol?
    private var refreshPending = false
    private var pendingOrigin: CGPoint?
    private var followingEnd = true
    private var documentHeight: CGFloat = 0
    private var scrollOrigin = CGPoint.zero
    private var followingUpdate = false

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
      if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
      boundsObserver = nil
      documentObserver = nil
      styledScrollView = nil
    }

    private func applyAppearance() {
      guard window != nil, let scrollView = enclosingScrollView else { return }
      if styledScrollView !== scrollView {
        stopObserving()
        styledScrollView = scrollView
        pendingOrigin = scrollPosition?.origin
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self, weak scrollView] _ in
          MainActor.assumeIsolated {
            guard let self, let scrollView else { return }
            if self.pendingOrigin == nil {
              self.scrollPosition?.origin = scrollView.contentView.bounds.origin
              let origin = scrollView.contentView.bounds.origin
              if !self.followingUpdate, origin != self.scrollOrigin {
                self.followingEnd = (scrollView.documentView?.frame.height ?? 0)
                  - scrollView.contentView.bounds.maxY <= 24
              }
              self.scrollOrigin = origin
            }
            self.refreshWhenAttached()
          }
        }
        if followsContent, let document = scrollView.documentView {
          document.postsFrameChangedNotifications = true
          documentObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: document, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWhenAttached() }
          }
        }
      }
      ScrollAppearance.apply(to: scrollView, persistentIndicators: persistentIndicators)
      if let origin = pendingOrigin, let document = scrollView.documentView,
        document.frame.height >= origin.y + scrollView.contentView.bounds.height {
        pendingOrigin = nil
        move(to: origin, in: scrollView)
      }
      if followsContent, let document = scrollView.documentView {
        let height = document.frame.height
        if pendingOrigin == nil, followingEnd, height != documentHeight {
          move(to: CGPoint(x: 0, y: max(0, height - scrollView.contentView.bounds.height)), in: scrollView)
        }
        documentHeight = height
      }
    }
    private func move(to origin: CGPoint, in scrollView: NSScrollView) {
      followingUpdate = true
      scrollView.contentView.scroll(to: origin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
      scrollOrigin = scrollView.contentView.bounds.origin
      followingUpdate = false
    }
  }
}
