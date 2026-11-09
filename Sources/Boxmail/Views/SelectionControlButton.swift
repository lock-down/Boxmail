import AppKit
import SwiftUI

/// Shared appearance for native selection buttons; AppKit owns menu tracking and keyboard input.
@MainActor class SelectionControlButton: NSPopUpButton {
  private var pointerInside = false
  private var hoverTracking: NSTrackingArea?
  override var isFlipped: Bool { true }
  override var alignmentRectInsets: NSEdgeInsets {
    NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: SettingsFormLayout.controlHeight)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let tracking = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(tracking)
    hoverTracking = tracking
  }
  override func mouseEntered(with event: NSEvent) {
    pointerInside = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    pointerInside = false
    needsDisplay = true
  }

  func drawSelectionSurface(visible: Bool = true) {
    let focused = cell?.showsFirstResponder == true
    let path = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      xRadius: UILayout.controlRadius, yRadius: UILayout.controlRadius)
    if visible {
      NSColor(
        isHighlighted
          ? Palette.blueSoft : pointerInside && isEnabled ? Palette.sidebar : Palette.canvas
      )
      .withAlphaComponent(isEnabled ? 1 : 0.55).setFill()
      path.fill()
    }
    if visible || focused {
      NSColor(
        focused ? Palette.blue : pointerInside && isEnabled ? Palette.border : Palette.softBorder
      )
      .withAlphaComponent(isEnabled ? 1 : 0.55).setStroke()
      path.lineWidth = focused ? 1.5 : 1
      path.stroke()
    }
  }

  func drawSelectionIndicator(x: CGFloat) {
    let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))?
      .withSymbolConfiguration(.init(paletteColors: [NSColor(Palette.muted)]))
    arrow?.draw(
      in: NSRect(x: x, y: (bounds.height - 6) / 2, width: 9, height: 6),
      from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true,
      hints: nil)
  }

  func drawIconSurface() {
    let path = NSBezierPath(
      roundedRect: bounds, xRadius: UILayout.iconRadius, yRadius: UILayout.iconRadius)
    NSColor(Palette.ink).withAlphaComponent(
      isEnabled ? (isHighlighted ? 0.08 : pointerInside ? 0.045 : 0) : 0
    ).setFill()
    path.fill()
    if cell?.showsFirstResponder == true {
      NSColor(Palette.blue).setFill()
      NSRect(x: (bounds.width - 12) / 2, y: bounds.height - 4, width: 12, height: 1).fill()
    }
  }
}
