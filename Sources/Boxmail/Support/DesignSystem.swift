import BoxmailCore
import SwiftUI

// Use the property wrapper explicitly when an SDK also exports a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
  static let blue = Color(hex: 0x256DE0), blueSoft = Color(hex: 0xE8F0FE),
    purple = Color(hex: 0x6D4AE0), purpleSoft = Color(hex: 0xF0EBFD)
  static let chrome = Color(hex: 0xEFF1F4), sidebar = Color(hex: 0xF2F3F6),
    canvas = Color(hex: 0xF7F8FA), border = Color(hex: 0xE2E5EA), softBorder = Color(hex: 0xEDEFF2)
  static let ink = Color(hex: 0x1B1F27), muted = Color(hex: 0x656D7A),
    success = Color(hex: 0x0E7854), amber = Color(hex: 0x966012)
}
extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: 1)
  }
}
struct ActionButton: View {
  var title: String
  var icon: String? = nil
  var kind: Kind = .normal
  var action: () -> Void
  enum Kind { case normal, primary, ai, softAI }
  var color: Color {
    kind == .ai || kind == .softAI
      ? Palette.purple : kind == .primary ? Palette.blue : Palette.muted
  }
  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        if let icon { Image(systemName: icon) }
        Text(title)
      }.font(.system(size: 12, weight: .medium)).foregroundStyle(
        kind == .primary || kind == .ai ? .white : color
      ).padding(.horizontal, 12).frame(height: 31).background(
        kind == .primary || kind == .ai ? color : kind == .softAI ? Palette.purpleSoft : .white,
        in: RoundedRectangle(cornerRadius: 7)
      ).overlay(
        RoundedRectangle(cornerRadius: 7).stroke(
          kind == .softAI ? Palette.purple.opacity(0.2) : Palette.border,
          lineWidth: kind == .ai || kind == .primary ? 0 : 1))
    }.buttonStyle(.plain)
  }
}
struct IconButton: View {
  let icon: String
  let help: String
  var color: Color = Palette.muted
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(
        width: 26, height: 28)
    }.buttonStyle(.plain).help(help).accessibilityLabel(help)
  }
}
struct Tag: View {
  var text: String
  var ai = false
  var body: some View {
    Text(text).font(.system(size: 10)).foregroundStyle(ai ? Palette.purple : Palette.blue).padding(
      .horizontal, 7
    ).padding(.vertical, 3).background(
      ai ? Palette.purpleSoft : Palette.blueSoft, in: RoundedRectangle(cornerRadius: 4))
  }
}
struct EmptyState: View {
  var title: String
  var subtitle: String
  var icon = "tray"
  var body: some View {
    VStack(spacing: 13) {
      Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(
        Palette.muted.opacity(0.6))
      Text(title).font(.system(size: 17, weight: .semibold))
      Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(
        .center
      ).frame(maxWidth: 350)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
  }
}
struct SectionCard<Content: View>: View {
  var title: String
  var icon: String = ""
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        if !icon.isEmpty { Image(systemName: icon).foregroundStyle(Palette.purple) }
        Text(title).font(.system(size: 14, weight: .semibold))
      }
      content()
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
      .white, in: RoundedRectangle(cornerRadius: 10)
    ).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.softBorder))
  }
}
func displayTime(_ iso: String) -> String {
  let parser = ISO8601DateFormatter()
  parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
    return iso
  }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "zh_CN")
  formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
  return formatter.string(from: date)
}
func fileSize(_ bytes: Int) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
