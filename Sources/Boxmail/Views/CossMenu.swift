import SwiftUI

enum CossMenuItem {
  case action(Action)
  case divider
  case heading(String)
  case note(String)
  case submenu(String, icon: AppicaGlyph? = nil, value: String? = nil, items: [Self])

  struct Action {
    let title: String
    let subtitle: String?
    let icon: AppicaGlyph?
    let swatch: Color?
    let shortcut: String?
    let mark: Mark
    let enabled: Bool
    let destructive: Bool
    let run: () -> Void
  }

  enum Mark {
    case none, choice(Bool), checkbox(Bool)

    var selected: Bool {
      switch self {
      case .none: return false
      case .choice(let selected), .checkbox(let selected): return selected
      }
    }
  }

  static func command(
    _ title: String, subtitle: String? = nil, icon: AppicaGlyph? = nil, swatch: Color? = nil, shortcut: String? = nil,
    mark: Mark = .none, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void
  ) -> Self {
    .action(Action(title: title, subtitle: subtitle, icon: icon, swatch: swatch, shortcut: shortcut, mark: mark,
      enabled: enabled, destructive: destructive, run: action))
  }

  var title: String {
    switch self {
    case .action(let action): return action.title
    case .submenu(let title, _, _, _): return title
    case .divider, .heading, .note: return ""
    }
  }

  var enabled: Bool {
    switch self {
    case .action(let action): return action.enabled
    case .submenu(_, _, _, let items): return items.contains(where: \.enabled)
    case .divider, .heading, .note: return false
    }
  }

  var height: CGFloat {
    switch self {
    case .divider: return 9
    case .heading, .note: return 24
    case .action(let action): return action.subtitle == nil ? 28 : 42
    case .submenu: return 28
    }
  }
}

@resultBuilder
enum CossMenuItems {
  static func buildExpression(_ item: CossMenuItem) -> [CossMenuItem] { [item] }
  static func buildExpression(_ items: [CossMenuItem]) -> [CossMenuItem] { items }
  static func buildBlock(_ parts: [CossMenuItem]...) -> [CossMenuItem] { parts.flatMap { $0 } }
  static func buildOptional(_ part: [CossMenuItem]?) -> [CossMenuItem] { part ?? [] }
  static func buildEither(first: [CossMenuItem]) -> [CossMenuItem] { first }
  static func buildEither(second: [CossMenuItem]) -> [CossMenuItem] { second }
  static func buildArray(_ parts: [[CossMenuItem]]) -> [CossMenuItem] { parts.flatMap { $0 } }
}

struct CossMenu<Trigger: View>: View {
  let title: String
  var value: String? = nil
  var width: CGFloat = 216
  var emphasis: ButtonEmphasis = .plain
  var prefersSelection = false
  @CossMenuItems var items: () -> [CossMenuItem]
  @ViewBuilder var trigger: () -> Trigger
  @ViewState private var isOpen = false

  var body: some View {
    Button { isOpen.toggle() } label: { trigger() }
      .buttonStyle(ControlFeedback(selected: isOpen, emphasis: emphasis)).controlFocus()
      .accessibilityLabel(title)
      .accessibilityValue(value.map { isOpen ? "\($0)，已展开" : $0 } ?? (isOpen ? "已展开" : "已收起"))
      .background {
        CossMenuAnchor(isOpen: $isOpen, items: items, width: width, prefersSelection: prefersSelection)
      }
      .onKeyPress(.downArrow) { isOpen = true; return .handled }
  }
}

struct CossMenuLabel: View {
  let title: String
  var detail: String? = nil
  var icon: AppicaGlyph? = nil
  var swatch: Color? = nil
  var size: UIControlSize = .regular
  var fillsWidth = false
  var color = Palette.ink

  var body: some View {
    HStack(spacing: 8) {
      if let swatch {
        let shape = RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous)
        shape.fill(swatch).overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
          .frame(width: 16, height: 16).accessibilityHidden(true)
      } else if let icon {
        AppicaIcon(icon).foregroundStyle(Palette.muted)
      }
      Text(title).lineLimit(1).truncationMode(.middle).layoutPriority(1)
      if fillsWidth { Spacer(minLength: 0) }
      if let detail { Text(detail).lineLimit(1).foregroundStyle(Palette.muted) }
      AppicaIcon(.chevronDown, size: UILayout.smallIconSize)
        .foregroundStyle(Palette.muted)
    }.font(size.font).foregroundStyle(color)
      .controlLabel(size: size, fillsWidth: fillsWidth, alignment: .leading)
  }
}

struct CossMenuPanel: View {
  let items: [CossMenuItem]
  let width: CGFloat
  let height: CGFloat
  let prefersSelection: Bool
  let isSubmenu: Bool
  let dismiss: () -> Void
  let dismissTree: () -> Void
  @FocusState private var focused: Int?
  @ViewState private var hovered: Int?
  @ViewState private var submenu: Int?

  static let inset = UILayout.menuInset
  static let maximumHeight: CGFloat = 344
  static func contentHeight(_ items: [CossMenuItem]) -> CGFloat {
    items.reduce(inset * 2) { $0 + $1.height }
  }

  private var selectable: [Int] { items.indices.filter { items[$0].enabled } }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: UILayout.menuRadius, style: .continuous)
    ScrollViewReader { reader in
      Group {
        if Self.contentHeight(items) > height {
          OverlayScrollView { rows }
        } else {
          rows
        }
      }
      .onChange(of: focused) { _, index in if let index { reader.scrollTo(index) } }
      .onKeyPress(.upArrow) { move(-1); return .handled }
      .onKeyPress(.downArrow) { move(1); return .handled }
      .onKeyPress(.home) { focused = selectable.first; return .handled }
      .onKeyPress(.end) { focused = selectable.last; return .handled }
      .onKeyPress(.rightArrow) {
        guard let focused, case .submenu = items[focused] else { return .ignored }
        submenu = focused
        return .handled
      }
      .onKeyPress(.leftArrow) {
        guard isSubmenu else { return .ignored }
        dismiss()
        return .handled
      }
      .onKeyPress(.escape) { dismiss(); return .handled }
      .onKeyPress(.tab) { dismissTree(); return .handled }
      .onKeyPress { press in
        guard press.modifiers.intersection([.command, .control, .option]).isEmpty,
          press.characters.first?.isLetter == true || press.characters.first?.isNumber == true else { return .ignored }
        let following = selectable.filter { $0 > (focused ?? -1) }
        if let match = (following + selectable).first(where: {
          items[$0].title.range(of: press.characters, options: [.anchored, .caseInsensitive]) != nil
        }) {
          focused = match
        }
        return .handled
      }
      .task {
        if prefersSelection, let selected = selectable.first(where: {
          if case .action(let action) = items[$0] { return action.mark.selected }
          return false
        }) {
          focused = selected
          reader.scrollTo(selected)
        } else {
          focused = selectable.first
        }
      }
    }
    .frame(width: width, height: height, alignment: .top)
    .background(Palette.paper, in: shape).clipShape(shape)
    .overlay { shape.strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false) }
    .accessibilityElement(children: .contain)
  }

  private var rows: some View {
    VStack(spacing: 0) {
      ForEach(items.indices, id: \.self) { index in
        row(items[index], index: index).id(index)
      }
    }.padding(Self.inset)
  }

  @ViewBuilder private func row(_ item: CossMenuItem, index: Int) -> some View {
    switch item {
    case .divider:
      Rectangle().fill(Palette.softBorder).frame(height: 1).padding(4)
        .accessibilityHidden(true)
    case .heading(let title):
      textRow(title).font(.system(size: 11, weight: .semibold)).accessibilityAddTraits(.isHeader)
    case .note(let message):
      textRow(message).font(UIType.small)
    case .action(let action):
      itemButton(item, index: index) {
        HStack(spacing: 8) {
          if let swatch = action.swatch {
            RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous).fill(swatch).frame(width: 16, height: 16)
              .overlay { RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous).strokeBorder(Palette.border) }
              .accessibilityHidden(true)
          } else if let icon = action.icon {
            AppicaIcon(icon).foregroundStyle(action.destructive ? Palette.destructive : Palette.muted)
              .frame(width: UILayout.iconSize).accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
            if let subtitle = action.subtitle {
              Text(subtitle).font(UIType.small).foregroundStyle(Palette.muted)
            }
          }.lineLimit(1).truncationMode(.middle)
          Spacer(minLength: 4)
          if let shortcut = action.shortcut {
            Text(shortcut).font(UIType.small).foregroundStyle(Palette.muted)
          }
          switch action.mark {
          case .choice(let selected):
            AppicaIcon(.check, size: UILayout.smallIconSize)
              .opacity(selected ? 1 : 0).accessibilityHidden(true)
          case .checkbox(let selected):
            CossCheckbox(isOn: selected).accessibilityHidden(true)
          case .none: EmptyView()
          }
        }.foregroundStyle(action.destructive ? Palette.destructive : Palette.ink)
      } activate: {
        dismissTree()
        DispatchQueue.main.async { action.run() }
      }
      .accessibilityAddTraits(action.mark.selected ? .isSelected : [])
    case .submenu(let title, let icon, let value, let options):
      itemButton(item, index: index) {
        HStack(spacing: 8) {
          if let icon {
            AppicaIcon(icon).foregroundStyle(Palette.muted).frame(width: UILayout.iconSize).accessibilityHidden(true)
          }
          Text(title).lineLimit(1)
          Spacer(minLength: 4)
          if let value { Text(value).lineLimit(1).truncationMode(.middle).foregroundStyle(Palette.muted) }
          AppicaIcon(.chevronRight, size: UILayout.smallIconSize)
            .foregroundStyle(Palette.muted).accessibilityHidden(true)
        }
      } activate: { submenu = index }
        .background {
          CossMenuAnchor(isOpen: Binding(get: { submenu == index }, set: {
            if !$0 && submenu == index { submenu = nil }
          }), items: { options }, width: 216, trailing: true, dismissTree: dismissTree)
        }
        .accessibilityValue(value ?? "")
    }
  }

  private func textRow(_ title: String) -> some View {
    Text(title).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.tail)
      .frame(maxWidth: .infinity, alignment: .leading).frame(height: 24).padding(.horizontal, 8)
      .cossTooltip(title)
  }

  private func itemButton<Label: View>(
    _ item: CossMenuItem, index: Int, @ViewBuilder label: () -> Label, activate: @escaping () -> Void
  ) -> some View {
    let highlighted = item.enabled && (hovered == index || (hovered == nil && focused == index) || submenu == index)
    return Button {
      focused = index
      activate()
    } label: {
      label().font(UIType.caption).padding(.horizontal, 8).frame(height: item.height)
        .contentShape(Rectangle())
        .background(highlighted ? Palette.sidebar : .clear,
          in: RoundedRectangle(cornerRadius: UILayout.menuRowRadius, style: .continuous))
    }
    .buttonStyle(.plain).focusable().focusEffectDisabled().focused($focused, equals: index)
    .onKeyPress(.return) { activate(); return .handled }
    .disabled(!item.enabled).opacity(item.enabled ? 1 : ControlStateAppearance.disabledOpacity)
    .cossTooltip(item.title)
    .onHover { over in
      if over {
        hovered = index
        if submenu != index { submenu = nil }
      } else if hovered == index {
        hovered = nil
      }
    }
  }

  private func move(_ offset: Int) {
    guard !selectable.isEmpty else { return }
    hovered = nil
    let index = selectable.firstIndex(where: { $0 == focused }) ?? (offset > 0 ? -1 : 0)
    focused = selectable[(index + offset + selectable.count) % selectable.count]
  }
}
