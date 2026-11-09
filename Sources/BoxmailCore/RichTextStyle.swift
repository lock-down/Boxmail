import AppKit
import Foundation

/// Portable inline styles use points and opaque sRGB; nil means the default.
public enum RichTextStyle {
  public static let defaultFontSize: Double = 14
  public static let fontSizeRange: ClosedRange<Double> = 8...72
  public static let fontSizes: [Double] = [
    8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72,
  ]
  public static let defaultColor = "#232D3D"

  public static func normalizedFontSize(_ value: Double?) -> Double? {
    guard let value, value.isFinite, fontSizeRange.contains(value) else { return nil }
    let rounded = (value * 100).rounded() / 100
    return rounded == defaultFontSize ? nil : rounded
  }

  public static func normalizedColor(_ value: String?) -> String? {
    guard let value, value.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
    else { return nil }
    let color = value.uppercased()
    return color == defaultColor ? nil : color
  }

  public static func nsColor(_ value: String?) -> NSColor {
    let hex = normalizedColor(value) ?? defaultColor
    let rgb = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(
      srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }

  public static func hexColor(_ value: NSColor) -> String? {
    guard let rgb = value.usingColorSpace(.sRGB) else { return nil }
    let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
      .map { Int((min(1, max(0, $0)) * 255).rounded()) }
    return normalizedColor(
      String(format: "#%02X%02X%02X", components[0], components[1], components[2]))
  }
}
