import SwiftUI

/// Workspaces keep a compact title, a quiet description and one trailing action group.
struct WorkspaceHeader<Actions: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 24) {
        heading
        Spacer(minLength: 16)
        actions().fixedSize()
      }
      VStack(alignment: .leading, spacing: 12) {
        heading
        actions()
      }
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(UIType.title).foregroundStyle(Palette.ink).tracking(-0.4)
        .accessibilityAddTraits(.isHeader)
      if !subtitle.isEmpty {
        Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
