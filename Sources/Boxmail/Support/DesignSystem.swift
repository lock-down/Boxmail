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
              : hovered && enabled
                ? (selected ? Palette.blue : Palette.ink).opacity(filled ? 0.08 : 0.045) : .clear
          ).allowsHitTesting(false)
        }
        .scaleEffect(configuration.isPressed && filled && !reduceMotion ? 0.98 : 1)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovered = $0 }
        .animation(UIMotion.feedback(reduceMotion), value: hovered)
        .animation(UIMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
  }
}

struct ActionButton: View {
  var title: String
  var icon: String? = nil
  var kind: Kind = .normal
  var action: () -> Void
  enum Kind { case normal, primary, ai, softAI }
  var body: some View {
    WorkflowAction(title: title, icon: icon, color: kind == .normal ? Palette.ink : Palette.blue, action: action)
  }
}

struct IconButton: View {
  let icon: String
  let help: String
  var color: Color = Palette.muted
  var size: CGFloat = 32
  var active = false
  let action: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 14, weight: .regular)).foregroundStyle(color)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        .symbolEffect(.bounce, value: active && !reduceMotion)
        .symbolEffectsRemoved(reduceMotion)
        .frame(width: size, height: size).contentShape(RoundedRectangle(cornerRadius: 7))
        .animation(UIMotion.feedback(reduceMotion), value: icon)
    }.buttonStyle(ControlFeedback()).focused($focused)
      .overlay(alignment: .bottom) {
        if focused { Rectangle().fill(Palette.blue).frame(width: 12, height: 1).padding(.bottom, 3).allowsHitTesting(false) }
      }
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? Palette.blue : Palette.muted)
        .padding(.horizontal, compact ? 9 : 12).frame(height: compact ? 28 : 32)
        .background(selected ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(ControlFeedback(selected: selected, corner: 6)).focused($focused)
      .overlay(alignment: .bottom) {
        if focused { Rectangle().fill(Palette.blue).frame(height: 1).padding(.horizontal, 9).allowsHitTesting(false) }
      }
      .accessibilityAddTraits(selected ? .isSelected : [])
      .animation(UIMotion.selection(reduceMotion), value: selected)
  }
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
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(Palette.muted)
        .frame(height: 42).padding(.bottom, 8).accessibilityHidden(true)
      Text(title).font(UIType.heading)
      Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(5)
        .multilineTextAlignment(.center).frame(maxWidth: 340)
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
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 9) {
        if !icon.isEmpty {
          Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Palette.muted)
            .frame(width: 18).accessibilityHidden(true)
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
