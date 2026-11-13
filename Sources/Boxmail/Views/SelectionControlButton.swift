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
    let focused = isEnabled && cell?.showsFirstResponder == true
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
    } else if isEnabled && (isHighlighted || pointerInside) {
      NSColor(Palette.ink).withAlphaComponent(ControlStateAppearance.overlayOpacity(
        enabled: isEnabled, pressed: isHighlighted, hovered: pointerInside)).setFill()
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

  func drawSelectionText(
    _ text: String, x: CGFloat, width: CGFloat, font: NSFont,
    color: Color, alignment: NSTextAlignment = .left
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    paragraph.alignment = alignment
    let height = ceil((text as NSString).size(withAttributes: [.font: font]).height)
    (text as NSString).draw(
      in: NSRect(x: x, y: (bounds.height - height) / 2, width: max(0, width), height: height),
      withAttributes: [
        .font: font,
        .foregroundColor: NSColor(color).withAlphaComponent(isEnabled ? 1 : 0.4),
        .paragraphStyle: paragraph,
      ])
  }

  func drawIconSurface() {
    let path = NSBezierPath(
      roundedRect: bounds, xRadius: UILayout.iconRadius, yRadius: UILayout.iconRadius)
    NSColor(Palette.ink).withAlphaComponent(
      ControlStateAppearance.overlayOpacity(
        enabled: isEnabled, pressed: isHighlighted, hovered: pointerInside)
    ).setFill()
    path.fill()
    if isEnabled && cell?.showsFirstResponder == true {
      let focus = NSBezierPath(
        roundedRect: bounds.insetBy(dx: 1, dy: 1),
        xRadius: UILayout.iconRadius, yRadius: UILayout.iconRadius)
      NSColor(Palette.blue).withAlphaComponent(ControlStateAppearance.focusOpacity).setStroke()
      focus.lineWidth = 2
      focus.stroke()
    }
  }
}
