import SwiftUI

/// Shared scroll boundary: chrome stays fixed while the supplied list content scrolls.
struct WorkspaceListSurface<Header: View, Content: View, Footer: View>: View {
  @ViewBuilder var header: () -> Header
  @ViewBuilder var content: () -> Content
  @ViewBuilder var footer: () -> Footer

  var body: some View {
    VStack(spacing: 0) {
      header()
      OverlayScrollView { content() }
      footer()
    }
    .background(Palette.paper)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.softBorder, lineWidth: 1)
        .allowsHitTesting(false)
    }
    .accessibilityElement(children: .contain)
  }
}

/// Data-driven rows use the same surface as richer summary and streaming lists.
struct WorkspaceList<Item: Identifiable, Header: View, Row: View, Footer: View>: View {
  let items: [Item]
  @ViewBuilder var header: () -> Header
  @ViewBuilder var footer: () -> Footer
  @ViewBuilder var row: (Item) -> Row

  var body: some View {
    WorkspaceListSurface {
      header()
    } content: {
      rows
    } footer: {
      footer()
    }
  }
  private var rows: some View {
    LazyVStack(spacing: 0) {
      ForEach(items) { item in
        row(item)
        if item.id != items.last?.id { Divider().overlay(Palette.softBorder) }
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
    .background(selected ? Palette.blueSoft : Palette.paper)
  }
}
