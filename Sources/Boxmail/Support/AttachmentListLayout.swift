import SwiftUI

/// Header and rows share exact column widths at each density.
struct AttachmentListLayout {
  static let inset: CGFloat = 16
  static let gap: CGFloat = 20
  static let icon: CGFloat = 24

  let showsSource, showsStatus: Bool
  let name, source, size, date, status, actions: CGFloat

  init(width: CGFloat) {
    showsSource = width >= 960
    showsStatus = width >= 760
    size = showsSource ? 96 : 64
    date = showsSource ? 112 : 84
    status = showsStatus ? (showsSource ? 96 : 72) : 0
    actions = UILayout.iconControl * 3 + UILayout.iconGap * 2
    let count = 5 + (showsSource ? 1 : 0) + (showsStatus ? 1 : 0)
    let gaps = CGFloat(count - 1) * Self.gap
    let flexible = max(0, width - Self.inset * 2 - Self.icon - size - date - status - actions - gaps)
    name = showsSource ? min(520, floor(flexible * 0.48)) : flexible
    source = showsSource ? flexible - name : 0
  }
}
