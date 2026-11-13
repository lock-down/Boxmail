import BoxmailCore
import SwiftUI

// Use the property wrapper explicitly when an SDK also exports a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
  static let blue = Color(hex: 0x3567AF), blueSoft = Color(hex: 0xEBF1FA)
  static let accent = blue, accentSoft = blueSoft
  static let chrome = Color(hex: 0xF8F9FB), sidebar = Color(hex: 0xF3F5F8),
    canvas = Color(hex: 0xF7F8FA), paper = Color.white,
    border = Color(hex: 0xD8DFE8), softBorder = Color(hex: 0xE9EDF2)
  static let ink = Color(hex: 0x232D3D), muted = Color(hex: 0x606E82),
    success = Color(hex: 0x28745B), amber = Color(hex: 0x98651F)
}
enum UILayout {
  static let sidebar: CGFloat = 216
  static let reading: CGFloat = 860
  static let document: CGFloat = 920
  static let pageInset: CGFloat = 28
  static let radius: CGFloat = 12
  static let controlRadius: CGFloat = 10
  static let navigationRadius: CGFloat = 12
  static let segmentRadius: CGFloat = controlRadius + 4
  static let iconControl: CGFloat = UIControlSize.regular.height
  static let iconSize: CGFloat = 14
  static let iconRadius: CGFloat = 8
  static let iconGap: CGFloat = 4
}
enum UIType {
  static let title = Font.system(size: 24, weight: .semibold)
  static let heading = Font.system(size: 17, weight: .semibold)
  static let section = Font.system(size: 14, weight: .semibold)
  static let body = Font.system(size: 13)
  static let caption = Font.system(size: 12)
  static let small = Font.system(size: 11)
}
extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: 1)
  }
}

func menuTitle(_ value: String, limit: Int = 34) -> String {
  guard value.count > limit else { return value }
  return String(value.prefix(limit - 10)) + "…" + String(value.suffix(9))
}
struct Tag: View {
  var text: String
  var ai = false
  var body: some View {
    Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
      .foregroundStyle(ai ? Palette.accent : Palette.muted).padding(.horizontal, 7).padding(
        .vertical, 3
      )
      .background(ai ? Palette.accentSoft : Palette.sidebar, in: RoundedRectangle(cornerRadius: 4))
  }
}
struct SenderAvatar: View {
  let name: String
  var size: CGFloat = 34
  var body: some View {
    Text(String(name.prefix(1))).font(.system(size: size * 0.4, weight: .medium))
      .foregroundStyle(Palette.blue).frame(width: size, height: size)
      .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: size * 0.3))
      .accessibilityHidden(true)
  }
}
struct EmptyState: View {
  var title: String
  var subtitle: String
  var icon = "tray"
  var actionTitle: String? = nil
  var actionDisabled = false
  var action: (() -> Void)? = nil
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(Palette.muted)
        .frame(height: 42).padding(.bottom, 8).accessibilityHidden(true)
      Text(title).font(UIType.heading)
      Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(5)
        .multilineTextAlignment(.center).frame(maxWidth: 340)
      if let actionTitle, let action {
        ActionButton(title: actionTitle, color: Palette.accent, action: action)
          .disabled(actionDisabled).padding(.top, 4)
      }
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
struct PageHeading: View {
  let title: String
  let subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(UIType.title).tracking(-0.4)
      Text(subtitle).font(UIType.body).foregroundStyle(Palette.muted).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
extension View {
  func workspacePage() -> some View {
    frame(maxWidth: .infinity, alignment: .leading).padding(UILayout.pageInset)
  }
}
struct SectionCard<Content: View>: View {
  var title: String
  var icon: String = ""
  var contentSpacing: CGFloat = 16
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: contentSpacing) {
      HStack(spacing: 9) {
        if !icon.isEmpty {
          Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.muted)
            .frame(width: 20, height: 20).accessibilityHidden(true)
        }
        Text(title).font(UIType.section)
      }
      content()
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
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
