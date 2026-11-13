import AppKit

@MainActor enum ScrollEventRouting {
  static func containsPointer(in view: NSView) -> Bool {
    guard let window = view.window else { return false }
    // A scrolling gesture can retain its original event location and target view.
    let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    // AppKit's visible rectangle can extend beyond the receiver into its ancestor's clip.
    return view.bounds.intersection(view.visibleRect).contains(point)
  }

  static func parentScrollView(of view: NSView) -> NSScrollView? {
    var ancestor = view.superview
    while let parent = ancestor {
      if let scroll = parent as? NSScrollView { return scroll }
      ancestor = parent.superview
    }
    return nil
  }
}
