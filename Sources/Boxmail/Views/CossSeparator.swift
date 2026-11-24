import SwiftUI

struct CossSeparator: View {
  var axis: Axis = .horizontal

  var body: some View {
    Rectangle().fill(Palette.softBorder)
      .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
      .accessibilityHidden(true).allowsHitTesting(false)
  }
}
