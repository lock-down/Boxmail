import SwiftUI

struct MailRecipientOverlay: View {
  let state: MailRecipientState

  var body: some View {
    let generation = state.generation
    ZStack(alignment: .topLeading) {
      ForEach(state.regions.filter { $0.width > 0 && $0.height > 0 }) { region in
        RecipientDetailsView(fields: region.fields)
          .frame(width: region.width, alignment: .leading).fixedSize(horizontal: false, vertical: true)
          .background(GeometryReader { geometry in
            Color.clear.preference(key: MailRecipientHeight.self, value: geometry.size.height)
          })
          .onPreferenceChange(MailRecipientHeight.self) { state.setHeight($0, for: region, generation: generation) }
          .offset(x: region.x, y: region.y)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).id(generation)
  }
}

private enum MailRecipientHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
