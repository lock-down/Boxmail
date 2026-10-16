import BoxmailCore
import SwiftUI

// Use the property wrapper explicitly when an SDK also exports a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
  static let blue = Color(hex: 0x3567AF), blueSoft = Color(hex: 0xEAF0F9)
  static let accent = blue, accentSoft = blueSoft
  static let chrome = Color(hex: 0xF5F7FA), sidebar = Color(hex: 0xF1F4F8),
    canvas = Color(hex: 0xF7F9FC), border = Color(hex: 0xDCE2EB), softBorder = Color(hex: 0xEBEFF5)
  static let ink = Color(hex: 0x202A3B), muted = Color(hex: 0x637086),
    success = Color(hex: 0x28745B), amber = Color(hex: 0x98651F)
}
enum UILayout {
  static let sidebar: CGFloat = 216
  static let reading: CGFloat = 860
}
extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: 1)
  }
}

/// Shared pointer feedback; native buttons retain keyboard and accessibility behavior.
struct ControlFeedback: ButtonStyle {
  var selected = false
  var filled = false
  var corner: CGFloat = 7
  func makeBody(configuration: Configuration) -> some View {
    FeedbackBody(configuration: configuration, selected: selected, filled: filled, corner: corner)
  }
  private struct FeedbackBody: View {
    let configuration: Configuration
    let selected: Bool
    let filled: Bool
    let corner: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovered = false
    var body: some View {
      configuration.label
        .overlay {
          RoundedRectangle(cornerRadius: corner).fill(
            configuration.isPressed
              ? Palette.ink.opacity(filled ? 0.16 : 0.08)
              : hovered && enabled ? Palette.ink.opacity(filled ? 0.07 : 0.035) : .clear
          ).allowsHitTesting(false)
        }
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: configuration.isPressed)
    }
  }
}

struct ActionButton: View {
  var title: String
  var icon: String? = nil
  var kind: Kind = .normal
  var action: () -> Void
  @FocusState private var focused: Bool
  enum Kind { case normal, primary, ai, softAI }
  private var filled: Bool { kind == .primary || kind == .ai }
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
        Text(title).lineLimit(1).fixedSize()
      }.font(.system(size: 12, weight: .medium))
        .foregroundStyle(filled ? .white : kind == .softAI ? Palette.accent : Palette.ink)
        .padding(.horizontal, 12).frame(height: 32)
        .background(
          filled ? Palette.blue : kind == .softAI ? Palette.accentSoft : .white,
          in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7).stroke(
            filled ? .clear : kind == .softAI ? Palette.blue.opacity(0.15) : Palette.border)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(ControlFeedback(filled: filled)).focused($focused)
      .overlay(
        RoundedRectangle(cornerRadius: 9).stroke(focused ? Palette.blue : .clear, lineWidth: 2)
          .padding(-2)
      )
      .accessibilityLabel(title)
  }
}
struct IconButton: View {
  let icon: String
  let help: String
  var color: Color = Palette.muted
  let action: () -> Void
  @FocusState private var focused: Bool
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 14, weight: .regular)).foregroundStyle(color)
        .frame(width: 32, height: 32).contentShape(RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(ControlFeedback()).focused($focused)
      .overlay(
        RoundedRectangle(cornerRadius: 8).stroke(focused ? Palette.blue : .clear, lineWidth: 2)
      )
      .help(help).accessibilityLabel(help)
  }
}
struct IconMenu<Content: View>: View {
  let icon: String
  let help: String
  @ViewBuilder var content: () -> Content
  var body: some View {
    Menu(content: content) {
      Image(systemName: icon).font(.system(size: 14, weight: .regular))
        .foregroundStyle(Palette.muted).frame(width: 32, height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .frame(width: 32, height: 32).help(help).accessibilityLabel(help)
  }
}
struct ChoiceMenu<Content: View>: View {
  let title: String
  var help = ""
  @ViewBuilder var content: () -> Content
  var body: some View {
    Menu(content: content) {
      HStack(spacing: 8) {
        Text(menuTitle(title, limit: 26)).font(.system(size: 12)).lineLimit(1)
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
          .foregroundStyle(Palette.muted)
      }.foregroundStyle(Palette.ink).padding(.horizontal, 10).frame(height: 32)
        .background(.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .help(help.isEmpty ? title : help).accessibilityLabel(help.isEmpty ? title : help)
  }
}
func menuTitle(_ value: String, limit: Int = 34) -> String {
  guard value.count > limit else { return value }
  return String(value.prefix(limit - 10)) + "…" + String(value.suffix(9))
}
struct FilterButton: View {
  let title: String
  var selected = false
  var compact = false
  let action: () -> Void
  @FocusState private var focused: Bool
  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? Palette.blue : Palette.muted)
        .padding(.horizontal, compact ? 9 : 12).frame(height: compact ? 28 : 32)
        .background(selected ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(ControlFeedback(selected: selected, corner: 6)).focused($focused)
      .overlay(
        RoundedRectangle(cornerRadius: 7).stroke(focused ? Palette.blue : .clear, lineWidth: 2)
      )
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
struct Tag: View {
  var text: String
  var ai = false
  var body: some View {
    Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
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
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(Palette.muted)
        .frame(width: 66, height: 66).background(
          Palette.sidebar, in: RoundedRectangle(cornerRadius: 20)
        )
        .padding(.bottom, 4)
      Text(title).font(.system(size: 17, weight: .semibold))
      Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
        .multilineTextAlignment(.center).frame(maxWidth: 340)
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
struct PageHeading: View {
  let title: String
  let subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
      Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
    }
  }
}
extension View {
  func workspacePage() -> some View {
    frame(maxWidth: .infinity, alignment: .leading).padding(28)
  }
}
struct SectionCard<Content: View>: View {
  var title: String
  var icon: String = ""
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 9) {
        if !icon.isEmpty { Image(systemName: icon).foregroundStyle(Palette.muted).frame(width: 18) }
        Text(title).font(.system(size: 14, weight: .semibold))
      }
      content()
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.softBorder))
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
