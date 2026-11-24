import SwiftUI

struct CossSpinner: View {
  var label: String? = nil
  var size: CGFloat = 16
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 8) {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
        let turns = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        RemixIcon(.loader4Line, size: size).foregroundStyle(Palette.muted)
          .rotationEffect(.degrees(reduceMotion ? 0 : turns * 360))
      }.frame(width: size, height: size).accessibilityHidden(true)
      if let label { Text(label).font(UIType.caption).foregroundStyle(Palette.muted) }
    }.accessibilityElement(children: .ignore).accessibilityLabel(label ?? "正在加载")
  }
}
