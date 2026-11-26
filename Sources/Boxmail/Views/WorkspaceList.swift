import SwiftUI

/// Shared scroll boundary: chrome stays fixed while the supplied list content scrolls.
struct WorkspaceListSurface<Header: View, Content: View, Footer: View>: View {
  var scrollPosition: ScrollPositionState? = nil
  var bordered = true
  @ViewBuilder var header: () -> Header
  @ViewBuilder var content: () -> Content
  @ViewBuilder var footer: () -> Footer

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header().background(Palette.canvas)
      OverlayScrollView(scrollPosition: scrollPosition) {
        content().frame(maxWidth: .infinity, alignment: .leading)
      }
      footer()
    }
    .framedSurface(bordered: bordered, radius: UILayout.workspaceRadius)
    .accessibilityElement(children: .contain)
  }
}

/// Data-driven rows use the same surface as richer summary and streaming lists.
struct WorkspaceList<Item: Identifiable, Header: View, Row: View, Footer: View>: View {
  let items: [Item]
  var emptyMessage: String? = nil
  var scrollPosition: ScrollPositionState? = nil
  var bordered = true
  @ViewBuilder var header: () -> Header
  @ViewBuilder var footer: () -> Footer
  @ViewBuilder var row: (Item) -> Row

  var body: some View {
    WorkspaceListSurface(scrollPosition: scrollPosition, bordered: bordered) {
      header()
    } content: {
      rows
    } footer: {
      footer()
    }
  }
  private var rows: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      if items.isEmpty, let emptyMessage {
        Text(emptyMessage).font(UIType.caption).foregroundStyle(Palette.muted)
          .frame(maxWidth: .infinity).padding(32)
      }
      ForEach(items) { item in
        row(item).id(item.id)
        if item.id != items.last?.id { CossSeparator() }
      }
    }
  }
}

/// Row feedback, focus and activation match the organizer; trailing actions stay independent.
struct WorkspaceListRow<Content: View, Actions: View>: View {
  var selected = false
  var primaryAction: (() -> Void)?
  let action: () -> Void
  @ViewBuilder var content: () -> Content
  @ViewBuilder var actions: () -> Actions
  @ViewState private var hovered = false
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    HStack(spacing: 0) {
      Button(action: action) {
        content().frame(maxWidth: .infinity, alignment: .leading)
          .padding(16).contentShape(Rectangle())
      }
      .buttonStyle(ControlFeedback(selected: selected, corner: 0)).controlFocus(corner: 0)
      .simultaneousGesture(TapGesture(count: 2).onEnded { primaryAction?() })
      .onKeyPress(.return) {
        (primaryAction ?? action)()
        return .handled
      }
      .accessibilityAddTraits(selected ? .isSelected : [])
      actions()
    }
    .background(selected ? Palette.selected : hovered && enabled ? Palette.canvas : Palette.paper)
    .onHover { hovered = $0 }
  }
}

extension View {
  /// Native selection and accessibility stay with List. The row owns its visible surface.
  func cossListStyle() -> some View {
    listStyle(.plain)
      .scrollContentBackground(.hidden)
      .contentMargins(.horizontal, 0, for: .scrollContent)
      .environment(\.defaultMinListRowHeight, 0)
      .tint(Palette.selected)
  }

  func cossListRow(selected: Bool) -> some View {
    modifier(CossListRowSurface(selected: selected))
      .listRowInsets(EdgeInsets(top: 0, leading: UILayout.listRowInset, bottom: 4, trailing: UILayout.listRowInset))
      .listRowSeparator(.hidden)
      .listRowBackground(Palette.paper)
  }
}

private struct CossListRowSurface: ViewModifier {
  let selected: Bool
  @ViewState private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: UILayout.listRowRadius, style: .continuous)
    content.frame(maxWidth: .infinity, alignment: .leading)
      .background(selected ? Palette.selected : hovered && enabled ? Palette.canvas : Palette.paper, in: shape)
      .overlay { shape.strokeBorder(selected ? Palette.border : Palette.softBorder).allowsHitTesting(false) }
      .contentShape(shape)
      .onHover { hovered = $0 }
  }
}
