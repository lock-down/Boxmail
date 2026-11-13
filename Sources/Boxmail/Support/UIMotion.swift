import SwiftUI

enum UIMotion {
  static func feedback(_ reduced: Bool) -> Animation {
    .easeOut(duration: reduced ? 0.08 : 0.14)
  }
  static func selection(_ reduced: Bool) -> Animation {
    .easeOut(duration: reduced ? 0.08 : 0.22)
  }
  static func disclosure(_ reduced: Bool) -> Animation? {
    reduced ? nil : .smooth(duration: 0.26, extraBounce: 0)
  }
  static func reveal(_ reduced: Bool) -> AnyTransition {
    reduced ? .opacity : .opacity.combined(with: .offset(y: -6))
  }
}
