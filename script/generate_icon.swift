import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
  FileHandle.standardError.write(
    Data("usage: swift script/generate_icon.swift <iconset-directory> [source.png]\n".utf8))
  exit(2)
}
let output = CommandLine.arguments[1]
let source =
  CommandLine.arguments.count > 2
  ? CommandLine.arguments[2] : "Sources/BoxmailCore/Resources/BoxmailMark.png"
let manager = FileManager.default
guard let data = manager.contents(atPath: source), let bitmap = NSBitmapImageRep(data: data),
  let original = bitmap.cgImage
else {
  throw NSError(
    domain: "BoxmailIcon", code: 1,
    userInfo: [NSLocalizedDescriptionKey: "无法读取图标源文件：\(source)"])
}

// The supplied artwork includes a light backdrop. Crop its outer five percent,
// then apply the same rounded tile mask used by the sidebar, without recoloring.
let insetX = CGFloat(original.width) * 0.05
let insetY = CGFloat(original.height) * 0.05
let crop = CGRect(
  x: insetX, y: insetY,
  width: CGFloat(original.width) - 2 * insetX,
  height: CGFloat(original.height) - 2 * insetY)
guard let artwork = original.cropping(to: crop) else {
  throw NSError(
    domain: "BoxmailIcon", code: 2,
    userInfo: [NSLocalizedDescriptionKey: "无法裁切图标源文件"])
}
let image = NSImage(
  cgImage: artwork,
  size: NSSize(width: CGFloat(artwork.width), height: CGFloat(artwork.height)))
try manager.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)).fill(using: .copy)
    let inset = CGFloat(pixels) * 0.075
    let ratio = min(
      (CGFloat(pixels) - 2 * inset) / image.size.width,
      (CGFloat(pixels) - 2 * inset) / image.size.height)
    let width = image.size.width * ratio
    let height = image.size.height * ratio
    let rect = NSRect(
      x: (CGFloat(pixels) - width) / 2,
      y: (CGFloat(pixels) - height) / 2, width: width, height: height)
    NSBezierPath(roundedRect: rect, xRadius: width * 0.25, yRadius: height * 0.25).addClip()
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: output).appendingPathComponent(name))
  }
}
