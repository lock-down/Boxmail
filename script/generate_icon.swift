import AppKit
import Foundation

let output = CommandLine.arguments[1]
let manager = FileManager.default
try manager.createDirectory(atPath: output, withIntermediateDirectories: true)
let symbol = NSImage(systemSymbolName: "envelope.fill", accessibilityDescription: nil)!
  .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(srgbRed: 37 / 255, green: 109 / 255, blue: 224 / 255, alpha: 1).setFill()
    let inset = CGFloat(pixels) * 0.075
    NSBezierPath(
      roundedRect: NSRect(
        x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset),
      xRadius: CGFloat(pixels) * 0.19, yRadius: CGFloat(pixels) * 0.19
    ).fill()
    let ratio = min(
      CGFloat(pixels) * 0.56 / symbol.size.width, CGFloat(pixels) * 0.56 / symbol.size.height)
    let width = symbol.size.width * ratio
    let height = symbol.size.height * ratio
    symbol.draw(
      in: NSRect(
        x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2, width: width,
        height: height))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: output).appendingPathComponent(name))
  }
}
