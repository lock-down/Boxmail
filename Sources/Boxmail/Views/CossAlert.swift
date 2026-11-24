import SwiftUI

struct CossAlertAction {
  let title: String
  var role: ButtonRole?
  var enabled: Bool
  let run: () -> Void

  init(_ title: String, role: ButtonRole? = nil, enabled: Bool = true, action: @escaping () -> Void = {}) {
    self.title = title
    self.role = role
    self.enabled = enabled
    run = action
  }

  var emphasis: ButtonEmphasis {
    if role == .cancel { return .plain }
    if role == .destructive { return .destructive }
    return .primary
  }
}

@resultBuilder
enum CossAlertActions {
  static func buildExpression(_ action: CossAlertAction) -> [CossAlertAction] { [action] }
  static func buildBlock(_ parts: [CossAlertAction]...) -> [CossAlertAction] { parts.flatMap { $0 } }
  static func buildOptional(_ actions: [CossAlertAction]?) -> [CossAlertAction] { actions ?? [] }
}

extension View {
  func cossAlert(
    _ title: String, isPresented: Binding<Bool>,
    @CossAlertActions actions: @escaping () -> [CossAlertAction], message: @escaping () -> Text
  ) -> some View {
    sheet(isPresented: isPresented) {
      CossAlertPanel(title: title, message: message(), actions: actions()) { isPresented.wrappedValue = false }
    }
  }

  func cossAlert<Item>(
    _ title: String, isPresented: Binding<Bool>, presenting item: Item?,
    @CossAlertActions actions: @escaping (Item) -> [CossAlertAction], message: @escaping (Item) -> Text
  ) -> some View {
    sheet(isPresented: isPresented) {
      if let item {
        CossAlertPanel(title: title, message: message(item), actions: actions(item)) { isPresented.wrappedValue = false }
      }
    }
  }
}

private struct CossAlertPanel: View {
  let title: String
  let message: Text
  let actions: [CossAlertAction]
  let dismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        Text(title).font(UIType.heading).accessibilityAddTraits(.isHeader)
        ViewThatFits(in: .vertical) {
          description.fixedSize(horizontal: false, vertical: true)
          OverlayScrollView { description }
        }.frame(maxHeight: 216, alignment: .top)
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      Rectangle().fill(Palette.softBorder).frame(height: 1)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        ForEach(actions.indices, id: \.self) { index in
          let action = actions[index]
          ActionButton(title: action.title, emphasis: action.emphasis, size: .form,
            minimumWidth: 72, role: action.role) {
            dismiss()
            action.run()
          }.disabled(!action.enabled)
            .keyboardShortcut(action.role == .cancel ? .cancelAction : action.role == .destructive ? nil : .defaultAction)
        }
      }.padding(.horizontal, 20).padding(.vertical, 12).background(Palette.canvas)
    }
    .frame(width: 420).fixedSize(horizontal: false, vertical: true)
    .foregroundStyle(Palette.ink).background(Palette.paper)
    .interactiveDismissDisabled()
    .onExitCommand { dismiss() }
  }

  private var description: some View {
    message.font(UIType.body).foregroundStyle(Palette.muted).lineSpacing(4).textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
