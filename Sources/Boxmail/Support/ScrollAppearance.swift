import AppKit

@MainActor enum ScrollAppearance {
  static func apply(to scrollView: NSScrollView) {
    if scrollView.borderType != .noBorder { scrollView.borderType = .noBorder }
    if scrollView.drawsBackground { scrollView.drawsBackground = false }
    if scrollView.focusRingType != .none { scrollView.focusRingType = .none }
    if scrollView.contentView.focusRingType != .none { scrollView.contentView.focusRingType = .none }
    if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
    if let layer = scrollView.layer, layer.borderWidth != 0 { layer.borderWidth = 0 }
    if let scroller = scrollView.verticalScroller, !(scroller is BorderlessOverlayScroller) {
      let visible = scrollView.hasVerticalScroller
      scrollView.verticalScroller = BorderlessOverlayScroller(copying: scroller)
      scrollView.hasVerticalScroller = visible
    }
    if let scroller = scrollView.horizontalScroller, !(scroller is BorderlessOverlayScroller) {
      let visible = scrollView.hasHorizontalScroller
      scrollView.horizontalScroller = BorderlessOverlayScroller(copying: scroller)
      scrollView.hasHorizontalScroller = visible
    }
    if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
  }

  static func applyRecursively(to view: NSView) {
    if let scrollView = view as? NSScrollView { apply(to: scrollView) }
    for child in view.subviews { applyRecursively(to: child) }
  }
}

/// AppKit keeps its native tracking, accessibility, and independent knob/track fading.
/// Only the knob is drawn, so hovering or focusing cannot reveal a bordered track.
final class BorderlessOverlayScroller: NSScroller {
  override class var isCompatibleWithOverlayScrollers: Bool { true }
  override var isOpaque: Bool { false }

  convenience init(copying scroller: NSScroller) {
    self.init(frame: scroller.frame)
    controlSize = scroller.controlSize
    target = scroller.target
    action = scroller.action
    isEnabled = scroller.isEnabled
    doubleValue = scroller.doubleValue
    knobProportion = scroller.knobProportion
    knobStyle = scroller.knobStyle
    focusRingType = .none
  }

  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

  override func drawKnob() {
    guard isEnabled, knobProportion < 1 else { return }
    let native = rect(for: .knob)
    guard !native.isEmpty else { return }
    let vertical = bounds.height > bounds.width
    let knob = vertical
      ? NSRect(x: bounds.maxX - 8, y: native.minY + 1, width: 6, height: max(0, native.height - 2))
      : NSRect(x: native.minX + 1, y: bounds.maxY - 8, width: max(0, native.width - 2), height: 6)
    (knobStyle == .light ? NSColor.white.withAlphaComponent(0.55)
      : NSColor.labelColor.withAlphaComponent(0.3)).setFill()
    NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
  }
}
