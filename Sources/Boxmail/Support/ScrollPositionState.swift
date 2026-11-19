import Foundation

/// A workspace retains only the position; native scroll views keep their own lifecycle.
@MainActor final class ScrollPositionState {
  var origin = CGPoint.zero
}
