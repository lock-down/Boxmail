import AppKit
import SwiftUI

extension View {
  func cossPopover<Popup: View>(
    isPresented: Binding<Bool>, arrowEdge: Edge = .bottom, alignment: HorizontalAlignment = .center,
    @ViewBuilder content: @escaping () -> Popup
  ) -> some View {
    background {
      CossPopoverAnchor(isPresented: isPresented, edge: arrowEdge, alignment: alignment, content: content)
    }
  }
}

private struct CossPopoverAnchor<Popup: View>: NSViewRepresentable {
  @Binding var isPresented: Bool
  let edge: Edge
  let alignment: HorizontalAlignment
  let content: () -> Popup

  func makeNSView(context: Context) -> CossMenuAnchorView { CossMenuAnchorView() }

  func updateNSView(_ view: CossMenuAnchorView, context: Context) {
    let state = $isPresented
    guard isPresented else {
      view.dismiss()
      return
    }
    let shape = RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous)
    let root = content()
      .foregroundStyle(Palette.ink).tint(Palette.accent)
      .toggleStyle(CossToggleStyle()).disclosureGroupStyle(SettingsDisclosureStyle())
      .environment(\.workspaceViewport, context.environment.workspaceViewport)
      .environment(\.colorScheme, context.environment.colorScheme)
      .fixedSize()
      .background(Palette.paper, in: shape).clipShape(shape)
      .overlay { shape.strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false) }
      .onExitCommand { state.wrappedValue = false }
    view.updatePopover(content: AnyView(root), edge: edge, alignment: alignment, didClose: { state.wrappedValue = false })
  }

  static func dismantleNSView(_ view: CossMenuAnchorView, coordinator: ()) { view.dismiss() }
}
