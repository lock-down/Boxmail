import AppKit
import BoxmailCore
import SwiftUI

struct CategoryTone {
  let ink: Color
  let fill: Color
  let swatch: Color

  struct Preset: Identifiable {
    let name, hex: String
    var id: String { hex }
    var color: Color { CategoryTone(hex: hex).swatch }
  }

  static let presets: [Preset] = [
    .init(name: "蓝色", hex: "#3567AF"), .init(name: "紫色", hex: "#7555AC"),
    .init(name: "琥珀色", hex: "#AC6514"), .init(name: "青色", hex: "#147D84"),
    .init(name: "玫红色", hex: "#AC4E73"), .init(name: "绿色", hex: "#3D7C3E"),
    .init(name: "红色", hex: "#B44942"), .init(name: "石板灰", hex: "#607084"),
  ]

  init(hex: String) {
    let value = Self.rgb(hex) ?? 0x607084
    let red = Double((value >> 16) & 255) / 255
    let green = Double((value >> 8) & 255) / 255
    let blue = Double(value & 255) / 255
    swatch = Color(hex: value)
    fill = Color(.sRGB, red: 0.80 + red * 0.20, green: 0.80 + green * 0.20, blue: 0.80 + blue * 0.20)
    // Keep colored text legible even when a custom swatch is very light.
    ink = Color(.sRGB, red: red * 0.43, green: green * 0.43, blue: blue * 0.43)
  }

  static func hex(for color: Color) -> String? {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
      Int((min(1, max(0, $0)) * 255).rounded())
    }
    return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
  }

  static func canonicalHex(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
    guard rgb(hex) != nil else { return nil }
    return hex.uppercased()
  }

  static func hex(for name: String, category: MailCategory?) -> String {
    if let hex = category?.color, rgb(hex) != nil { return hex.uppercased() }
    let defaults = ["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来"]
    if name == "未分类" { return presets[7].hex }
    if let index = defaults.firstIndex(of: name) { return presets[index].hex }
    let index = (category?.id ?? name).utf8.reduce(0) { ($0 * 31 + Int($1)) % 5 }
    return presets[index].hex
  }

  static func suggestedHex(in categories: [MailCategory]) -> String {
    let used = Dictionary(grouping: categories.filter { $0.id != "unclassified" }) { hex(for: $0.name, category: $0) }
    return (presets.min { used[$0.hex, default: []].count < used[$1.hex, default: []].count } ?? presets[0]).hex
  }

  private static func rgb(_ hex: String) -> UInt32? {
    let digits = hex.dropFirst()
    guard hex.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
    return UInt32(digits, radix: 16)
  }
}

extension MailStore {
  func categoryTone(_ name: String) -> CategoryTone {
    CategoryTone(hex: CategoryTone.hex(for: name, category: categories.first { $0.name == name }))
  }
}
